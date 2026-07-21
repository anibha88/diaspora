# frozen_string_literal: true

module HelperMethods
  def inlined_jobs
    # Ensure we're using the :test adapter so jobs are captured
    adapter = ActiveJob::Base.queue_adapter
    unless adapter.is_a?(ActiveJob::QueueAdapters::TestAdapter)
      raise "inlined_jobs requires the :test queue adapter"
    end

    result = yield

    # Drain all enqueued jobs by executing them directly.
    # This mirrors Sidekiq::Worker.drain_all behavior: jobs run synchronously
    # and errors propagate to the caller (no retry_on interception).
    while adapter.enqueued_jobs.any?
      job_data = adapter.enqueued_jobs.shift
      job_class = job_data[:job].is_a?(String) ? job_data[:job].constantize : job_data[:job]
      args = ActiveJob::Arguments.deserialize(job_data[:args])
      job_class.new.perform(*args)
    end

    result
  end
end
