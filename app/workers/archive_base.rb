# frozen_string_literal: true

#   Copyright (c) 2010-2011, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

module Workers
  class ArchiveBase < Base
    sidekiq_options queue: :low

    include Diaspora::Logging

    def perform(*args)
      if currently_running_archive_jobs >= AppConfig.settings.archive_jobs_concurrency.to_i
        logger.info "Already the maximum number of parallel archive jobs running, " \
                    "scheduling #{self.class}:#{args} in 5 minutes."
        self.class.perform_in(5.minutes + rand(30), *args)
      else
        perform_archive_job(*args)
      end
    end

    private

    def perform_archive_job(_args)
      raise NotImplementedError, "You must override perform_archive_job"
    end

    # Count how many ArchiveBase-derived jobs are currently in-flight
    # (excluding this one). Under Sidekiq this used Sidekiq::Workers.new;
    # under GoodJob the equivalent is a query against the good_jobs table
    # for rows that have been picked up (performed_at set) but not yet
    # finished (finished_at nil), whose job_class is one of the
    # ArchiveBase subclasses.
    def currently_running_archive_jobs
      archive_classes = ArchiveBase.subclasses.map(&:to_s)
      return 0 if archive_classes.empty?

      scope = GoodJob::Job.where(job_class: archive_classes)
                          .where.not(performed_at: nil)
                          .where(finished_at: nil)

      # Exclude the currently-executing job so a solo run still counts as
      # zero (mirrors the pid+thread check the Sidekiq version had).
      scope = scope.where.not(active_job_id: job_id) if respond_to?(:job_id) && job_id
      scope.count
    rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished
      # If we can't reach the good_jobs table (e.g. running specs that
      # never installed the GoodJob migration), fall through as if no
      # other job were running — this preserves the previous test-env
      # tolerance the Sidekiq version had for a missing Redis.
      0
    end
  end
end
