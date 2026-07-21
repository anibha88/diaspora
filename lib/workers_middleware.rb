# frozen_string_literal: true

# Replacement for the former SidekiqMiddlewares::CleanAndShortBacktraces.
# Wraps job execution and, on failure, replaces the raised exception's
# backtrace with a Rails-cleaned + length-limited copy before re-raising.
# Length is driven by the same AppConfig knob as before (backtrace was
# under [environment.sidekiq]; it now lives under [environment.good_job]).

module WorkersMiddleware
  module CleanAndShortBacktraces
    extend ActiveSupport::Concern

    included do
      around_perform do |_job, block|
        block.call
      rescue Exception # rubocop:disable Lint/RescueException
        backtrace = Rails.backtrace_cleaner.clean($!.backtrace || [])
        backtrace.reject! {|line| line =~ %r{lib/workers_middleware\.rb} }
        limit = AppConfig.environment.good_job.backtrace.get
        limit = limit ? limit.to_i : 0
        backtrace = [] if limit.zero?
        raise $!, $!.message, backtrace[0..limit]
      end
    end
  end
end
