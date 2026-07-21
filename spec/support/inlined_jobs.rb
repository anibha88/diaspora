# frozen_string_literal: true

module HelperMethods
  # Runs the given block, then performs every job enqueued during it -- the
  # ActiveJob/GoodJob equivalent of the former Sidekiq
  # `clear_all` / yield / `drain_all` helper.
  #
  # This is deliberately self-contained (it drives the ActiveJob :test adapter
  # directly rather than ActiveJob::TestHelper) because it is also mixed into
  # non-example objects such as User (see spec/support/user_methods.rb), where
  # the TestHelper instance methods are not available.
  #
  # The yielded object exposes `drain_all` for the (rare) specs that flush the
  # queue part-way through the block.
  def inlined_jobs
    test_adapter.enqueued_jobs.clear
    test_adapter.performed_jobs.clear
    result = yield InlinedJobsQueue.new
    InlinedJobsQueue.drain_all
    result
  end

  def test_adapter
    ActiveJob::Base.queue_adapter
  end

  # Small adapter so `queue.drain_all` inside an inlined_jobs block keeps working.
  class InlinedJobsQueue
    # Performs enqueued jobs repeatedly until the queue drains, so jobs that
    # enqueue further jobs (federation send/receive, retries, ...) run too --
    # matching Sidekiq's recursive drain_all.
    def self.drain_all
      adapter = ActiveJob::Base.queue_adapter
      until adapter.enqueued_jobs.empty?
        jobs = adapter.enqueued_jobs.dup
        adapter.enqueued_jobs.clear
        jobs.each do |job|
          # Each entry carries the ActiveJob-serialized payload under string keys
          # (job_class, arguments, ...) plus :job/:args/:queue convenience keys.
          # execute replays the serialized payload through the full job lifecycle
          # (around_perform; retries re-enqueue into the adapter).
          serialized = job.reject {|key, _| key.is_a?(Symbol) }
          ActiveJob::Base.execute(serialized)
        end
      end
    end

    def drain_all
      self.class.drain_all
    end
  end
end
