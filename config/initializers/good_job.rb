# frozen_string_literal: true

#   Copyright (c) 2010-2011, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

# Recurring background job schedule (formerly owned by sidekiq-cron).
#
# Note: ActiveJob serializes the current I18n locale with each job and restores
# it on perform, so the mail workers keep sending in the right locale without
# the dedicated Sidekiq i18n middleware we used before.
#
# Some recurring jobs can take a lot of resources, and others even ping other
# pods (recurring_pod_check). Having all jobs run at 0 UTC causes a high local
# load, as well as a little bit of DDoSing through the network as pods try to
# ping each other. So we give the daily jobs a random offset. Unlike the old
# sidekiq-cron setup (which persisted the generated times to config/schedule.yml)
# we simply pick a fresh random daily time at each boot -- that is enough to
# spread load across pods and across restarts.
def diaspora_cron_schedule
  random_hour = rand(24)
  random_minute = rand(60)
  randomized_daily = "#{random_minute} #{random_hour} * * *"

  {
    check_birthday:          {cron: "0 0 * * *",      class: "Workers::CheckBirthday"},
    clean_cached_files:      {cron: randomized_daily,  class: "Workers::CleanCachedFiles"},
    cleanup_old_exports:     {cron: randomized_daily,  class: "Workers::CleanupOldExports"},
    cleanup_pending_photos:  {cron: randomized_daily,  class: "Workers::CleanupPendingPhotos"},
    queue_users_for_removal: {cron: randomized_daily,  class: "Workers::QueueUsersForRemoval"},
    recheck_scheduled_pods:  {cron: "*/30 * * * *",    class: "Workers::RecheckScheduledPods"},
    recurring_pod_check:     {cron: randomized_daily,  class: "Workers::RecurringPodCheck"}
  }
end

Rails.application.configure do
  # Use ActiveJob's :test adapter under RSpec so jobs are recorded/controllable
  # and never touch the GoodJob tables; GoodJob everywhere else. Set on the
  # base class (an initializer runs too late for config.active_job.queue_adapter
  # to be picked up reliably).
  ActiveSupport.on_load(:active_job) do
    self.queue_adapter = Rails.env.test? ? :test : :good_job
  end

  # GoodJob v4 default: lower priority number runs first. Make it explicit so
  # the numeric priorities set on Workers::Base reproduce Sidekiq's strict queue
  # order urgent > high > medium > low > default.
  config.good_job.smaller_number_is_higher_priority = true

  # Run jobs in a separate `good_job` process (see Procfile), not inside Puma.
  config.good_job.execution_mode = :external

  # Match the former Sidekiq concurrency setting.
  config.good_job.max_threads = AppConfig.environment.workers.concurrency.to_i

  # Preserved failed/finished jobs are cleaned up after the former Sidekiq dead
  # job timeout window.
  config.good_job.cleanup_preserved_jobs_before_seconds_ago =
    AppConfig.environment.workers.dead_jobs_timeout.to_i

  # Only the job-runner process should own the cron scheduler.
  config.good_job.enable_cron = true
  config.good_job.cron = diaspora_cron_schedule
end
