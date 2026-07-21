# frozen_string_literal: true

# Configures GoodJob (background job backend) and installs the recurring cron
# schedule. Replaces:
#   * config/initializers/sidekiq.rb           (server/client wiring)
#   * config/initializers/sidekiq_scheduled.rb (cron schedule + randomization)
#   * lib/sidekiq_middlewares.rb               (backtrace cleaner, now an
#                                               around_perform on Workers::Base)

# Defined at the top so config.good_job.cron below can call GoodJobSchedule.build
# while this initializer is loading. Kept as a plain module (not autoloaded)
# because the classic autoloader (see config/application.rb) won't discover
# constants defined inside config/initializers/.
module GoodJobSchedule
  module_function

  # Build the cron hash consumed by GoodJob. Keys are the cron_key (used by
  # GoodJob to identify a recurring entry); values are the cron expression
  # plus the class to enqueue.
  def build
    {
      check_birthday:          {
        cron:  "0 0 * * *",
        class: "Workers::CheckBirthday"
      },
      clean_cached_files:      {
        cron:  daily_random_cron,
        class: "Workers::CleanCachedFiles"
      },
      cleanup_old_exports:     {
        cron:  daily_random_cron,
        class: "Workers::CleanupOldExports"
      },
      cleanup_pending_photos:  {
        cron:  daily_random_cron,
        class: "Workers::CleanupPendingPhotos"
      },
      queue_users_for_removal: {
        cron:  daily_random_cron,
        class: "Workers::QueueUsersForRemoval"
      },
      recheck_scheduled_pods:  {
        cron:  "*/30 * * * *",
        class: "Workers::RecheckScheduledPods"
      },
      recurring_pod_check:     {
        cron:  daily_random_cron(exclude_midnight_utc: true),
        class: "Workers::RecurringPodCheck"
      }
    }
  end

  # A "M H * * *" cron entry with random minute and hour. When
  # `exclude_midnight_utc:` is true, keep rolling until we do not land on the
  # DDoS-spike slot (used for recurring_pod_check).
  def daily_random_cron(exclude_midnight_utc: false)
    loop do
      minute = rand(60)
      hour = rand(24)
      cron = "#{minute} #{hour} * * *"
      return cron unless exclude_midnight_utc && cron == "0 0 * * *"
    end
  end
end

Rails.application.configure do
  # ---------------------------------------------------------------------------
  # Runtime wiring
  # ---------------------------------------------------------------------------
  # execution_mode :external means "only the dedicated `good_job start` worker
  # process actually executes jobs" — web dynos only enqueue. This matches how
  # Sidekiq was operated (one puma process, one sidekiq process).
  config.good_job.execution_mode = Rails.env.test? ? :inline : :external
  config.good_job.preserve_job_records = true
  config.good_job.retry_on_unhandled_error = false
  config.good_job.max_threads = AppConfig.environment.good_job.concurrency.to_i
  config.good_job.queues = "urgent;high;medium;low;default"
  config.good_job.cleanup_preserved_jobs_before_seconds_ago =
    AppConfig.environment.good_job.dead_jobs_timeout.to_i

  # Some recurring background jobs can take a lot of resources, and others
  # even include pinging other pods (like recurring_pod_check). Having all
  # jobs run at 0 UTC causes a high local load, as well as a little bit of
  # DDoSing through the network as pods try to ping each other simultaneously.
  # GoodJob-cron supports fixed cron expressions, so we generate the
  # randomized ones at boot (once per process — the offsets stay stable for
  # the lifetime of the worker).
  config.good_job.cron = GoodJobSchedule.build
end
