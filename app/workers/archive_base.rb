# frozen_string_literal: true

#   Copyright (c) 2010-2011, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

module Workers
  class ArchiveBase < Base
    diaspora_queue :low

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

    # Count archive jobs (any ArchiveBase subclass) that GoodJob is currently
    # executing, excluding this job itself. Replaces the former Sidekiq::Workers
    # thread introspection with a query against GoodJob's job table.
    def currently_running_archive_jobs
      archive_job_classes = ArchiveBase.subclasses.map(&:to_s)

      GoodJob::Job
        .where.not(performed_at: nil)
        .where(finished_at: nil)
        .where(job_class: archive_job_classes)
        .where.not(active_job_id: job_id)
        .count
    rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished
      # If code gets to this point and the GoodJob tables can't be queried, we're
      # running in a test environment and have not mocked the running-jobs count,
      # so we're not testing the concurrency-limiting behavior.
      0
    end
  end
end
