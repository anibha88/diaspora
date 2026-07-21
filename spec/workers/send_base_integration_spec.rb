# frozen_string_literal: true

# Integration spec for Workers::SendBase's hand-rolled retry pipeline.
#
# The existing send_base_spec covers seconds_to_delay in isolation; the
# per-worker specs (send_public_spec, send_private_spec) cover a single
# retry iteration in isolation. Neither of them exercises the full loop:
#
#   perform -> schedule_retry -> perform_in(delay, ...) -> new perform -> ...
#
# until either urls_to_retry is empty or MaxRetriesReached fires.
#
# The Sidekiq -> GoodJob migration replaces the perform_in mechanism, so we
# lock the composite behaviour here: correct delay ballpark at each attempt,
# correct max-retry cutoffs for the two "kinds" of send targets, and that
# schedule_retry short-circuits when there is nothing to retry.

describe Workers::SendBase do
  let(:sender_id) { "any_user@example.org" }
  let(:xml)       { "<xml>post</xml>" }
  let(:urls)      { ["https://example.org/receive/public"] }

  describe "#schedule_retry" do
    let(:worker) { Workers::SendBase.new }

    it "yields the current-attempt delay when under the per-object limit" do
      yielded_delay = nil
      yielded_count = nil

      worker.send(:schedule_retry, 1, sender_id, "status_message@guid", urls) do |delay, count|
        yielded_delay = delay
        yielded_count = count
      end

      # attempt 1 -> ((1+3)^4) + rand(30)*(1+1) = 256..315
      expect(yielded_delay).to be_between(256, 315)
      expect(yielded_count).to eq(1)
    end

    it "keeps yielding increasing delays across attempts up to MAX_RETRIES-1" do
      max = Workers::SendBase::MAX_RETRIES

      (1...max).each do |count|
        yielded = nil
        worker.send(:schedule_retry, count, sender_id, "status_message@guid", urls) do |delay, _|
          yielded = delay
        end
        expect(yielded).to be >= ((count + 3)**4)
      end
    end

    it "raises MaxRetriesReached at MAX_RETRIES for regular objects" do
      max = Workers::SendBase::MAX_RETRIES

      expect {
        worker.send(:schedule_retry, max, sender_id, "status_message@guid", urls) do |_, _|
          # should not be reached
          raise "schedule_retry yielded past the max"
        end
      }.to raise_error(Workers::SendBase::MaxRetriesReached)
    end

    it "grants Contact-typed objects an additional 10 retries before giving up" do
      max = Workers::SendBase::MAX_RETRIES

      # Still within the extended window: must yield, not raise.
      yielded = false
      worker.send(:schedule_retry, max + 5, sender_id, "Contact:acct@example.org", urls) do |_, _|
        yielded = true
      end
      expect(yielded).to be true

      # At the extended cutoff: must raise.
      expect {
        worker.send(:schedule_retry, max + 10, sender_id, "Contact:acct@example.org", urls) do |_, _|
          raise "schedule_retry yielded past the extended max"
        end
      }.to raise_error(Workers::SendBase::MaxRetriesReached)
    end
  end

  describe "full retry loop through SendPublic" do
    # Drive SendPublic end-to-end: each perform re-invocation is fed back in
    # via the perform_in args stub, up to MaxRetriesReached. This mirrors
    # what Sidekiq does today and what GoodJob will need to keep doing.
    let(:failing_urls) { urls }

    before do
      allow(DiasporaFederation::Federation::Sender).to receive(:public).and_return(failing_urls)
    end

    it "reschedules with monotonically-non-decreasing base delay and finally raises" do
      captured_delays = []

      # Redirect perform_in to a synchronous re-invocation of perform, capturing
      # the delay each time. Stop once we hit the terminal raise.
      allow(Workers::SendPublic).to receive(:perform_in) do |delay, *args|
        captured_delays << delay
        Workers::SendPublic.new.perform(*args)
      end

      expect {
        Workers::SendPublic.new.perform(sender_id, "status_message@guid", urls, xml)
      }.to raise_error(Workers::SendBase::MaxRetriesReached)

      # We should have gone through MAX_RETRIES scheduling attempts before
      # giving up (attempts 1..MAX_RETRIES-1 each schedule the next one; the
      # final call is what raises).
      max = Workers::SendBase::MAX_RETRIES
      expect(captured_delays.length).to eq(max - 1)

      # Base-delay component (excluding the rand jitter) grows strictly.
      base_delays = captured_delays.each_with_index.map { |_d, i| ((i + 1 + 3)**4) }
      expect(base_delays).to eq(base_delays.sort)
      captured_delays.each_with_index do |delay, i|
        count = i + 1
        expect(delay).to be >= ((count + 3)**4)
      end
    end
  end
end
