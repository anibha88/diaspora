# frozen_string_literal: true

#   Copyright (c) 2010-2011, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

module Workers
  # ActiveJob-backed base for every background worker in the app. Runs on top of
  # GoodJob (DB-backed) but keeps the historical `perform_async` / `perform_in`
  # API surface so every call site — models, controllers, the federation
  # dispatcher, and the specs that mock enqueues — continues to work unchanged.
  class Base < ApplicationJob
    include Diaspora::Logging

    # Retry policy is configured per-subclass in Workers::Base.inherited so it
    # can be overridden by workers with custom retry semantics (SendBase sets
    # its own attempt loop via perform_in and needs `attempts: 1` here).
    def self.inherited(subclass)
      super
      configured_attempts = AppConfig.environment.good_job.retry.get
      attempts = configured_attempts ? configured_attempts.to_i : 0
      # ActiveJob wants attempts >= 1 (1 == no retry); map 0 to 1.
      attempts = 1 if attempts < 1
      subclass.retry_on StandardError, attempts: attempts
    end

    # Enqueue immediately. Kept for API compatibility with the pre-migration
    # Sidekiq::Worker#perform_async signature.
    def self.perform_async(*args)
      perform_later(*args)
    end

    # Enqueue with a delay. Accepts:
    #   * a Duration (5.minutes) — treated as wait
    #   * a Numeric of seconds  — treated as wait
    #   * a Time / DateTime     — treated as wait_until (Sidekiq's perform_in
    #     accepted absolute times as well, several call sites rely on that)
    def self.perform_in(interval, *args)
      if interval.is_a?(Time) || interval.is_a?(DateTime)
        set(wait_until: interval).perform_later(*args)
      else
        set(wait: interval).perform_later(*args)
      end
    end

    # Alias historical Sidekiq method for parity — some callers use perform_at.
    def self.perform_at(time, *args)
      set(wait_until: time).perform_later(*args)
    end

    # Trim backtraces on failure to the configured limit. Replaces the
    # CleanAndShortBacktraces Sidekiq server middleware.
    around_perform do |_job, block|
      block.call
    rescue Exception # rubocop:disable Lint/RescueException
      backtrace = Rails.backtrace_cleaner.clean($!.backtrace || [])
      backtrace.reject! {|line| line =~ %r{app/workers/base\.rb} }
      limit = AppConfig.environment.good_job.backtrace.get
      limit = limit ? limit.to_i : 0
      backtrace = [] if limit.zero?
      raise $!, $!.message, backtrace[0..limit]
    end
  end
end
