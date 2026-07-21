# frozen_string_literal: true

#   Copyright (c) 2010-2011, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

module Workers
  class Base < ActiveJob::Base
    include Diaspora::Logging

    # Numeric priorities mapped from the former Sidekiq queue names. GoodJob is
    # configured with smaller_number_is_higher_priority, so lower numbers run
    # first -- reproducing Sidekiq's strict queue order:
    # urgent > high > medium > low > default.
    QUEUE_PRIORITIES = {
      urgent:  10,
      high:    20,
      medium:  30,
      low:     40,
      default: 50
    }.freeze

    # Sets both the ActiveJob queue name and the numeric priority for a worker,
    # so a subclass can keep declaring its queue the same conceptual way it did
    # with `sidekiq_options queue: :urgent`.
    def self.diaspora_queue(name)
      queue_as name
      queue_with_priority QUEUE_PRIORITIES.fetch(name.to_sym)
    end

    # Default queue/priority for workers that never declared one (Sidekiq used
    # the :default queue in that case).
    diaspora_queue :default

    # Reproduce Sidekiq's configurable retry-with-backoff. Sidekiq retried
    # `retry` times with an exponential-ish backoff before moving a job to the
    # dead set; ActiveJob's :polynomially_longer wait is the closest equivalent.
    # `attempts` counts total tries, so it is retry-count + 1.
    retry_attempts = (rt = AppConfig.environment.workers.retry.get) ? rt.to_i : 10
    retry_on StandardError, wait: :polynomially_longer, attempts: retry_attempts + 1

    # Reimplements the former SidekiqMiddlewares::CleanAndShortBacktraces server
    # middleware: on failure, clean and truncate the backtrace to the configured
    # limit before the exception propagates (so retries/logs stay readable).
    around_perform do |_job, block|
      begin
        block.call
      rescue Exception => e # rubocop:disable Lint/RescueException
        backtrace = Rails.backtrace_cleaner.clean(e.backtrace || [])
        backtrace.reject! {|line| line =~ %r{app/workers/base\.rb} }
        limit = (bt = AppConfig.environment.workers.backtrace.get) ? bt.to_i : 0
        backtrace = [] if limit.zero?
        raise e.class, e.message, backtrace[0..limit]
      end
    end

    class << self
      # Backwards-compatible enqueue API. The app enqueues jobs with the Sidekiq
      # style `Worker.perform_async(*args)` / `Worker.perform_in(delay, *args)`
      # in many places (models, controllers, federation, and workers' own
      # retries). These delegate to ActiveJob so those call sites keep working
      # unchanged after the move to GoodJob.
      def perform_async(*args)
        perform_later(*args)
      end

      # Sidekiq's perform_in accepted either a numeric interval (seconds from
      # now) or an absolute time; keep that contract so call sites like
      # `perform_in(remove_at + 1.day, ...)` (an absolute Time) still work.
      def perform_in(interval, *args)
        if interval.is_a?(Numeric)
          set(wait: interval).perform_later(*args)
        else
          set(wait_until: interval).perform_later(*args)
        end
      end
      alias_method :perform_at, :perform_in
    end
  end
end
