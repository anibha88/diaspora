# frozen_string_literal: true

#   Copyright (c) 2010-2011, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

require "workers_middleware"

module Workers
  # Base class for every Workers::* job.
  #
  # This class used to `include Sidekiq::Worker`. It now inherits from
  # ActiveJob (via ApplicationJob) and runs on GoodJob. To keep the ~40
  # call sites across the app (`Workers::Foo.perform_async(...)`, etc.)
  # unchanged, we expose a small compatibility shim that maps the Sidekiq
  # class-level API onto the ActiveJob equivalent:
  #
  #   perform_async(*args)          -> perform_later(*args)
  #   perform_in(interval, *args)   -> set(wait: interval).perform_later(*args)
  #   perform_at(time, *args)       -> set(wait_until: time).perform_later(*args)
  #
  # We also accept the legacy `sidekiq_options queue: :x, retry: n` DSL and
  # translate it to `queue_as :x` + `retry_on` config, so worker subclasses
  # keep working during the transition (their tests, too). A hash form of
  # the accumulated options is exposed via `.sidekiq_options` for the small
  # number of specs that assert on it.
  class Base < ApplicationJob
    include Diaspora::Logging
    include WorkersMiddleware::CleanAndShortBacktraces

    # Default queue + retry behaviour mirrors what the old sidekiq_options
    # line on this class encoded.
    queue_as :default

    default_retries = AppConfig.environment.good_job.retry.get
    DEFAULT_RETRIES = (default_retries ? default_retries.to_i : 10)

    # Retry with a growing delay (~3s, ~18s, ~83s, ...) — same shape as
    # ActiveJob's :polynomially_longer strategy in Rails 7.1+, hand-rolled
    # here so we work on Rails 6.1 too.
    retry_on StandardError,
             wait:     ->(attempt) { ((attempt**4) + 2) + (rand * (attempt + 1)) },
             attempts: DEFAULT_RETRIES + 1

    class << self
      # ---- Sidekiq API compatibility shim -----------------------------

      # Kept public because a handful of controllers/models test-mock
      # `expect(Workers::X).to receive(:perform_async)`.
      def perform_async(*args)
        perform_later(*args)
      end

      # Sidekiq's perform_in accepted a Duration, an Integer number of
      # seconds, OR an absolute Time (a few production call sites pass a
      # `Time` computed from user-flagged deletion windows). ActiveJob's
      # `set` splits those into `wait:` vs `wait_until:` — normalise here
      # so the shim accepts everything the old API accepted.
      def perform_in(interval, *args)
        if interval.is_a?(Time) || interval.is_a?(ActiveSupport::TimeWithZone)
          set(wait_until: interval).perform_later(*args)
        else
          set(wait: interval).perform_later(*args)
        end
      end

      def perform_at(time, *args)
        set(wait_until: time).perform_later(*args)
      end

      # ---- sidekiq_options DSL compatibility --------------------------

      # Accept the old `sidekiq_options queue: :urgent, retry: 0` form so
      # subclass files can be migrated incrementally. We translate the two
      # keys we actually use (queue, retry) into their ActiveJob
      # equivalents and record the raw hash so `.sidekiq_options` still
      # returns something specs can inspect.
      def sidekiq_options(opts = nil)
        return _sidekiq_options_hash if opts.nil?

        opts.each do |key, value|
          case key.to_sym
          when :queue
            queue_as value
          when :retry
            configure_retries(value)
          when :backtrace
            # handled globally by WorkersMiddleware::CleanAndShortBacktraces;
            # nothing to do here.
          else
            # Silently accept unknown keys for forward compat rather than
            # blowing up if a future worker passes an option we don't
            # recognise; log at debug level so it's still traceable.
            Rails.logger.debug { "Workers::Base ignored unknown sidekiq_options key: #{key}" }
          end
          (@_sidekiq_options_own ||= {})[key.to_s] = value
        end
      end

      private

      def configure_retries(value)
        # `retry: 0` on Sidekiq meant "no automatic retries, we handle
        # them ourselves" (SendBase does this). Under ActiveJob the
        # equivalent is to discard on any unhandled StandardError.
        if value.to_i.zero?
          discard_on StandardError
        else
          retry_on StandardError,
                   wait:     ->(attempt) { ((attempt**4) + 2) + (rand * (attempt + 1)) },
                   attempts: value.to_i + 1
        end
      end

      # Merged hash of every sidekiq_options key registered on this class
      # or any ancestor Workers::* class. Read-only view.
      def _sidekiq_options_hash
        merged = {
          "queue"     => queue_name,
          "retry"     => DEFAULT_RETRIES,
          "backtrace" => AppConfig.environment.good_job.backtrace.get.to_i
        }
        ancestors.grep(Class).reverse_each do |klass|
          own = klass.instance_variable_get(:@_sidekiq_options_own)
          merged.merge!(own.transform_keys(&:to_s)) if own
        end
        merged["queue"] = queue_name # queue_as wins over any recorded value
        merged
      end
    end
  end
end
