# frozen_string_literal: true

#   Copyright (c) 2010-2011, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

module Workers
  class ArchiveBase < Base
    queue_as :low

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

    # Count *other* in-flight archive jobs (i.e. running or scheduled) by
    # querying GoodJob's `good_jobs` table directly. Excludes the current job
    # so a running archive doesn't count itself as blocking.
    def currently_running_archive_jobs
      archive_class_names = ArchiveBase.subclasses.map(&:name)
      current_job_id = try(:job_id) || provider_job_id

      scope = GoodJob::Job
                .where(job_class: archive_class_names)
                .where(finished_at: nil)
      scope = scope.where.not(active_job_id: current_job_id) if current_job_id
      scope.count
    rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished, NameError
      # If the good_jobs table isn't reachable (e.g. tests that don't stub it)
      # fall back to 0 — matches the pre-migration behavior where a missing
      # Redis connection was treated as "no other jobs running". Production
      # cannot hit this path because diaspora* refuses to boot without a DB.
      0
    end
  end
end
