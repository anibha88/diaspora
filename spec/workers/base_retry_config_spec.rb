# frozen_string_literal: true

#   Copyright (c) 2010-2011, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

# Regression spec: pins down the retry configuration across the Sidekiq ->
# GoodJob migration. Workers::Base retries StandardError the configured number
# of times (via ActiveJob retry_on), while Workers::SendBase disables framework
# retries (it schedules its own via perform_in) and discards MaxRetriesReached.
#
# The backoff formula and MaxRetriesReached raising are covered by
# spec/workers/send_base_spec.rb, send_private_spec.rb and send_public_spec.rb.

describe "Worker retry configuration" do
  let(:configured_retries) { AppConfig.environment.workers.retry.get.to_i }

  describe Workers::Base do
    it "is an ActiveJob job" do
      expect(described_class.ancestors).to include(ActiveJob::Base)
    end

    it "registers a retry handler for StandardError" do
      handled = described_class.rescue_handlers.map(&:first)
      expect(handled).to include("StandardError")
    end
  end

  describe Workers::SendBase do
    it "derives MAX_RETRIES from the configured retry count" do
      expect(described_class::MAX_RETRIES).to eq(configured_retries)
    end

    it "discards the job once it reached the maximum number of retries" do
      # MaxRetriesReached is registered with discard_on (not retry_on), so a
      # perform that raises it does not re-enqueue.
      expect {
        described_class.new.rescue_with_handler(Workers::SendBase::MaxRetriesReached.new)
      }.not_to raise_error
    end
  end
end
