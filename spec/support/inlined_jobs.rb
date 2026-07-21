# frozen_string_literal: true

# Runs `block` and executes every job enqueued during it synchronously
# before returning. Replaces the pre-migration Sidekiq drain-all helper.
#
# The yielded object exposes a `drain_all` shim so pre-existing callers that
# invoke `queue.drain_all` inside the block (e.g. spec/integration/receiving_spec)
# keep working. `drain_all` runs any jobs enqueued so far, then returns.
module HelperMethods
  # Wraps ActiveJob's test adapter to expose Sidekiq's `drain_all` verb.
  class InlinedJobQueue
    include ActiveJob::TestHelper

    def drain_all
      perform_enqueued_jobs
    end
  end

  def inlined_jobs
    adapter = ActiveJob::Base.queue_adapter
    adapter.enqueued_jobs.clear if adapter.respond_to?(:enqueued_jobs)
    adapter.performed_jobs.clear if adapter.respond_to?(:performed_jobs)

    result = nil
    queue = InlinedJobQueue.new
    queue.perform_enqueued_jobs do
      result = yield(queue)
    end
    result
  end
end
