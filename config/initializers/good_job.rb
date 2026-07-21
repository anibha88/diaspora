# frozen_string_literal: true

# Some recurring background jobs can take a lot of resources, and others even
# include pinging other pods, like recurring_pod_check. Having all jobs run at
# 0 UTC causes a high local load, as well as a little bit of DDoSing through
# the network, as pods try to ping each other.
#
# To avoid this, we randomize the cron times for most jobs.

Rails.application.configure do
  config.good_job.execution_mode = Rails.env.test? ? :inline : :external
  config.good_job.queues = "urgent,high,medium,low,default"
  config.good_job.max_threads = AppConfig.environment.sidekiq.concurrency.to_i
  config.good_job.poll_interval = 5 # seconds

  random_hour = lambda { rand(24) }
  random_minute = lambda { rand(60) }

  config.good_job.enable_cron = true
  config.good_job.cron = {
    check_birthday: {
      cron:  "0 0 * * *",
      class: "Workers::CheckBirthday"
    },

    clean_cached_files: {
      cron:  "#{random_minute.call} #{random_hour.call} * * *",
      class: "Workers::CleanCachedFiles"
    },

    cleanup_old_exports: {
      cron:  "#{random_minute.call} #{random_hour.call} * * *",
      class: "Workers::CleanupOldExports"
    },

    cleanup_pending_photos: {
      cron:  "#{random_minute.call} #{random_hour.call} * * *",
      class: "Workers::CleanupPendingPhotos"
    },

    queue_users_for_removal: {
      cron:  "#{random_minute.call} #{random_hour.call} * * *",
      class: "Workers::QueueUsersForRemoval"
    },

    recheck_scheduled_pods: {
      cron:  "*/30 * * * *",
      class: "Workers::RecheckScheduledPods"
    },

    recurring_pod_check: {
      cron:  "#{random_minute.call} #{random_hour.call} * * *",
      class: "Workers::RecurringPodCheck"
    }
  }
end

# Set connection pool to match concurrency
database_url = ENV["DATABASE_URL"]
if database_url
  ENV["DATABASE_URL"] = "#{database_url}?pool=#{AppConfig.environment.sidekiq.concurrency.get}"
  ActiveRecord::Base.establish_connection
end

# Make sure each process has its own sequence of UUIDs
UUID.generator.next_sequence
