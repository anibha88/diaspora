# frozen_string_literal: true

require "active_job/test_helper"

# Preserves the public contract of the previous Sidekiq-era helper:
#
#   inlined_jobs do |worker_class|
#     Workers::Foo.perform_async(...)
#   end
#
# Every job enqueued inside the block runs before the block returns, and
# the block's return value is passed through to the caller. The
# worker-class argument (formerly Sidekiq::Worker) is now
# ActiveJob::Base — a stand-in that lets callers keep the old signature.
#
# We temporarily swap the ActiveJob queue adapter to :test so jobs
# accumulate on ActiveJob's in-memory queue and can be drained
# synchronously; this preserves the "enqueue then drain" semantics the
# integration specs expect. Outside this helper the test env runs
# GoodJob in :inline mode (see config/initializers/good_job.rb).
module HelperMethods
  include ActiveJob::TestHelper

  def inlined_jobs
    previous_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs

    result = nil
    perform_enqueued_jobs do
      result = yield ActiveJob::Base
    end
    result
  ensure
    ActiveJob::Base.queue_adapter = previous_adapter
  end
end
