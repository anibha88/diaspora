# frozen_string_literal: true

# Regression tests that lock in the migration from Sidekiq to GoodJob:
#
#   * queue priority ordering is declared in config/good_job.yml AND on the
#     individual worker classes (queue_as :urgent/:high/:medium/:low)
#   * the cron schedule installed by config/initializers/good_job.rb loads
#     the seven expected recurring jobs and preserves the randomization
#     guarantees the pre-migration sidekiq_scheduled.rb held
#   * perform_in(delay, ...) via Workers::Base actually enqueues a delayed
#     job through the GoodJob adapter

require "spec_helper"

describe "GoodJob configuration" do
  describe "queue priority" do
    it "orders queues urgent > high > medium > low > default in the GoodJob config" do
      config = Rails.application.config.good_job.queues
      expect(config).to eq("urgent;high;medium;low;default")
    end

    it "assigns each worker class to the queue it used to declare via sidekiq_options" do
      {
        Workers::ReceiveBase           => :urgent,
        Workers::FetchWebfinger        => :urgent,
        Workers::ResetPassword         => :urgent,
        Workers::ReceiveLocal          => :high,
        Workers::DeferredDispatch      => :high,
        Workers::DeferredRetraction    => :high,
        Workers::GatherOEmbedData      => :medium,
        Workers::GatherOpenGraphData   => :medium,
        Workers::FetchPublicPosts      => :medium,
        Workers::SendBase              => :medium,
        Workers::ProcessPhoto          => :low,
        Workers::DeleteAccount         => :low,
        Workers::CheckBirthday         => :low,
        Workers::RecheckScheduledPods  => :low,
        Workers::RecurringPodCheck     => :low,
        Workers::CleanCachedFiles      => :low,
        Workers::CleanupOldExports     => :low,
        Workers::CleanupPendingPhotos  => :low,
        Workers::QueueUsersForRemoval  => :low,
        Workers::RemoveOldUser         => :low,
        Workers::ExportPhotos          => :low,
        Workers::ArchiveBase           => :low,
        Workers::Mail::NotifierBase    => :low,
        Workers::Mail::InviteEmail     => :low,
        Workers::Mail::ReportWorker    => :low
      }.each do |klass, expected_queue|
        expect(klass.new.queue_name).to eq(expected_queue.to_s),
                                        "#{klass} expected queue #{expected_queue}, got #{klass.new.queue_name}"
      end
    end
  end

  describe "cron schedule" do
    let(:schedule) { GoodJobSchedule.build }

    it "installs all seven recurring entries" do
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

    it "runs check_birthday at midnight UTC daily" do
      expect(schedule[:check_birthday][:cron]).to eq("0 0 * * *")
    end

    it "runs recheck_scheduled_pods every 30 minutes" do
      expect(schedule[:recheck_scheduled_pods][:cron]).to eq("*/30 * * * *")
    end

    it "generates a valid cron string for each randomized entry" do
      %i[clean_cached_files cleanup_old_exports cleanup_pending_photos
         queue_users_for_removal recurring_pod_check].each do |key|
        expect(schedule[key][:cron]).to match(/\A\d{1,2} \d{1,2} \* \* \*\z/)
      end
    end

    it "never lands recurring_pod_check on 0 0 * * * (would DDoS the network)" do
      100.times do
        expect(GoodJobSchedule.daily_random_cron(exclude_midnight_utc: true)).not_to eq("0 0 * * *")
      end
    end

    it "points each entry at a real Workers class" do
      schedule.each_value do |entry|
        klass = entry[:class].constantize
        expect(klass).to be < Workers::Base
      end
    end
  end

  describe "perform_in delay via the ActiveJob shim" do
    include ActiveJob::TestHelper

    it "schedules the job with a wait matching the requested delay" do
      Workers::CheckBirthday.perform_in(5.minutes)
      job = ActiveJob::Base.queue_adapter.enqueued_jobs.last

      expect(job[:job]).to eq(Workers::CheckBirthday)
      expect(job[:at]).to be_within(2).of((Time.current + 5.minutes).to_f)
    end

    it "perform_async enqueues immediately (no scheduled_at)" do
      Workers::CheckBirthday.perform_async
      job = ActiveJob::Base.queue_adapter.enqueued_jobs.last

      expect(job[:job]).to eq(Workers::CheckBirthday)
      expect(job[:at]).to be_nil
    end
  end
end
