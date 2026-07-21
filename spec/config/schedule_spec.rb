# frozen_string_literal: true

#   Copyright (c) 2010-2011, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

# Regression spec: pins down the recurring-job schedule across the Sidekiq ->
# GoodJob migration. GoodJob's cron config must schedule the same 7 jobs at the
# same cadence, including the randomized daily jobs.
#
# The schedule is built by the top-level diaspora_cron_schedule method (defined
# in config/initializers/good_job.rb) and wired into config.good_job.cron.

describe "GoodJob cron schedule" do
  let(:schedule) { diaspora_cron_schedule }

  it "defines exactly the expected recurring jobs" do
    expect(schedule.keys).to contain_exactly(
      :check_birthday,
      :clean_cached_files,
      :cleanup_old_exports,
      :cleanup_pending_photos,
      :queue_users_for_removal,
      :recheck_scheduled_pods,
      :recurring_pod_check
    )
  end

  it "maps each job to the correct worker class" do
    expect(schedule[:check_birthday][:class]).to eq("Workers::CheckBirthday")
    expect(schedule[:clean_cached_files][:class]).to eq("Workers::CleanCachedFiles")
    expect(schedule[:cleanup_old_exports][:class]).to eq("Workers::CleanupOldExports")
    expect(schedule[:cleanup_pending_photos][:class]).to eq("Workers::CleanupPendingPhotos")
    expect(schedule[:queue_users_for_removal][:class]).to eq("Workers::QueueUsersForRemoval")
    expect(schedule[:recheck_scheduled_pods][:class]).to eq("Workers::RecheckScheduledPods")
    expect(schedule[:recurring_pod_check][:class]).to eq("Workers::RecurringPodCheck")
  end

  it "runs check_birthday daily at midnight UTC" do
    expect(schedule[:check_birthday][:cron]).to eq("0 0 * * *")
  end

  it "runs recheck_scheduled_pods every 30 minutes" do
    expect(schedule[:recheck_scheduled_pods][:cron]).to eq("*/30 * * * *")
  end

  # These jobs can be resource-heavy or ping other pods, so they must run once a
  # day at a randomized time (never at a fixed, coordinated 0 UTC) to avoid a
  # local load spike and a network-wide thundering herd.
  randomized_daily = %i[
    clean_cached_files
    cleanup_old_exports
    cleanup_pending_photos
    queue_users_for_removal
    recurring_pod_check
  ]

  randomized_daily.each do |job|
    it "schedules #{job} once daily at a randomized minute/hour" do
      minute, hour, day, month, weekday = schedule[job][:cron].split

      expect(minute.to_i).to be_between(0, 59)
      expect(hour.to_i).to be_between(0, 23)
      expect(day).to eq("*")
      expect(month).to eq("*")
      expect(weekday).to eq("*")
    end
  end

  it "does not schedule recurring_pod_check at the coordinated midnight time" do
    expect(schedule[:recurring_pod_check][:cron]).not_to eq("0 0 * * *")
  end

  it "is wired into GoodJob's cron config" do
    expect(Rails.application.config.good_job.cron.keys).to match_array(schedule.keys)
  end
end
