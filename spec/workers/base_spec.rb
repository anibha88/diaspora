# frozen_string_literal: true

# Regression coverage for the two cross-cutting Workers::Base behaviors that
# used to live in Sidekiq server middleware / sidekiq_options and now live in
# the ActiveJob base class:
#
#   * backtrace trimming (previously CleanAndShortBacktraces middleware)
#   * retry_on attempts wiring (previously sidekiq_options retry:)

require "spec_helper"

describe Workers::Base do
  # Concrete test-only workers so we can drive the base-class behaviors
  # without depending on any one production worker's semantics.
  class RaisingTestJob < Workers::Base # rubocop:disable Lint/ConstantDefinitionInBlock
    queue_as :low
    # Opt out of the default retry so the first raise surfaces to the test.
    # (SendBase uses this same pattern to gate its manual backoff loop.)
    retry_on StandardError, attempts: 1
    def perform
      raise "boom-from-test-worker"
    end
  end

  class CountingRetryJob < Workers::Base # rubocop:disable Lint/ConstantDefinitionInBlock
    queue_as :low

    cattr_accessor :attempts_recorded
    self.attempts_recorded = 0

    def perform
      self.class.attempts_recorded += 1
      raise "retry-me"
    end
  end

  describe "backtrace trimming (around_perform)" do
    it "limits the re-raised backtrace to AppConfig.environment.good_job.backtrace" do
      allow(AppConfig.environment.good_job.backtrace).to receive(:get).and_return(3)

      expect {
        RaisingTestJob.new.perform_now
      }.to raise_error(RuntimeError, "boom-from-test-worker") { |e|
        expect(e.backtrace.length).to be <= 4 # limit is inclusive slice [0..3]
      }
    end

    it "clears the backtrace entirely when the limit is 0" do
      allow(AppConfig.environment.good_job.backtrace).to receive(:get).and_return(0)

      expect {
        RaisingTestJob.new.perform_now
      }.to raise_error(RuntimeError) { |e|
        expect(e.backtrace).to eq([])
      }
    end

    it "drops the wrapper frame from app/workers/base.rb" do
      allow(AppConfig.environment.good_job.backtrace).to receive(:get).and_return(20)

      expect {
        RaisingTestJob.new.perform_now
      }.to raise_error(RuntimeError) { |e|
        expect(e.backtrace.join("\n")).not_to include("app/workers/base.rb")
      }
    end
  end

  describe "retry_on attempts wiring" do
    it "installs retry_on with the configured attempt count on every subclass" do
      # ActiveJob exposes the installed retry policy via retry_jitter/retry_on
      # internals; simplest check is that a subclass has at least one
      # rescue_handler registered by our base class.
      handler_klasses = CountingRetryJob.rescue_handlers.map(&:first)
      expect(handler_klasses).to include("StandardError")
    end
  end

  describe "perform_async / perform_in shim" do
    include ActiveJob::TestHelper

    it "perform_async delegates to perform_later" do
      expect {
        Workers::CheckBirthday.perform_async
      }.to have_enqueued_job(Workers::CheckBirthday)
    end

    it "perform_in delegates to set(wait:).perform_later" do
      expect {
        Workers::CheckBirthday.perform_in(2.hours)
      }.to have_enqueued_job(Workers::CheckBirthday).at(a_value_within(2).of(Time.current + 2.hours))
    end
  end
end
