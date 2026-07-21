# frozen_string_literal: true

# Runtime + cron configuration for GoodJob.
#
# GoodJob replaces the old Sidekiq + sidekiq-cron pair. Queue names, queue
# priority order, retry counts and the schedule of recurring jobs are all
# preserved from the previous config/sidekiq.yml and
# config/initializers/sidekiq_scheduled.rb.

# ---- Cron schedule helpers -------------------------------------------
#
# Some recurring background jobs can take a lot of resources, and others
# even include pinging other pods (recurring_pod_check). Having all jobs
# run at 0 UTC causes a high local load, as well as a little bit of
# DDoSing through the network as pods try to ping each other. The Sidekiq
# version generated random hour/minute values at boot; GoodJob's cron
# equally accepts a plain cron string, so we keep the exact same
# generator shape (including the config-file regeneration guard).

# rubocop:disable Metrics/MethodLength
def default_job_config
  random_hour = lambda { rand(24) }
  random_minute = lambda { rand(60) }

  {
    check_birthday:          {
      "cron":  "0 0 * * *",
      "class": "Workers::CheckBirthday"
    },

    clean_cached_files:      {
      "cron":  "#{random_minute.call} #{random_hour.call} * * *",
      "class": "Workers::CleanCachedFiles"
    },

    cleanup_old_exports:     {
      "cron":  "#{random_minute.call} #{random_hour.call} * * *",
      "class": "Workers::CleanupOldExports"
    },

    cleanup_pending_photos:  {
      "cron":  "#{random_minute.call} #{random_hour.call} * * *",
      "class": "Workers::CleanupPendingPhotos"
    },

    queue_users_for_removal: {
      "cron":  "#{random_minute.call} #{random_hour.call} * * *",
      "class": "Workers::QueueUsersForRemoval"
    },

    recheck_scheduled_pods:  {
      "cron":  "*/30 * * * *",
      "class": "Workers::RecheckScheduledPods"
    },

    recurring_pod_check:     {
      "cron":  "#{random_minute.call} #{random_hour.call} * * *",
      "class": "Workers::RecurringPodCheck"
    }
  }
end
# rubocop:enable Metrics/MethodLength

def valid_config?(path)
  return false unless File.exist?(path)

  current_config = YAML.load_file(path)

  # If the keys don't match the current default config keys, a new job
  # has been added, so we need to regenerate the config to have the new
  # job running.
  return false unless current_config.keys == default_job_config.keys

  # If recurring_pod_check is still running at midnight UTC, the config
  # file is probably from a previous version, and that's bad, so we need
  # to regenerate.
  current_config[:recurring_pod_check][:cron] != "0 0 * * *"
end

def regenerate_config(path)
  job_config = default_job_config
  File.open(path, "w") do |schedule_file|
    schedule_file.write(job_config.to_yaml)
  end
end

# ---- GoodJob runtime config ------------------------------------------

Rails.application.configure do
  # Strict-priority queue ordering. Same 5 queues as config/sidekiq.yml,
  # same order (urgent first, default last). GoodJob's `;` separator
  # groups queues; within a group, the numeric priority (`:N`) is used.
  config.good_job.queues = "urgent:5;high:4;medium:3;low:2;default:1"
  config.good_job.queue_select_limit = 5

  config.good_job.execution_mode = if Rails.env.test?
                                     :inline
                                   elsif Rails.env.development?
                                     :async
                                   else
                                     :external
                                   end

  config.good_job.max_threads = AppConfig.environment.good_job.concurrency.get.to_i

  # Keep completed job records around so operators can inspect them via
  # /good_job, and expire them on the same 6-week window Sidekiq's
  # dead_jobs_timeout used to give.
  config.good_job.preserve_job_records = true
  config.good_job.cleanup_preserved_jobs_before_seconds_ago =
    AppConfig.environment.good_job.preserved_jobs_timeout.get.to_i

  # Load the cron schedule from config/schedule.yml, regenerating it
  # first if the file is missing / stale (same guard as before).
  schedule_file_path = Rails.root.join("config", "schedule.yml")
  regenerate_config(schedule_file_path) unless valid_config?(schedule_file_path)

  schedule = YAML.load_file(schedule_file_path)
  config.good_job.enable_cron = true
  config.good_job.cron = schedule.transform_values do |entry|
    {cron: entry[:cron], class: entry[:class]}
  end
end
