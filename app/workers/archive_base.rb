# frozen_string_literal: true

#   Copyright (c) 2010-2011, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

module Workers
  class ArchiveBase < Base
    queue_as :low

    def perform(*args)
      if currently_running_archive_jobs >= AppConfig.settings.archive_jobs_concurrency.to_i
        logger.info "Already the maximum number of parallel archive jobs running, " \
                    "scheduling #{self.class}:#{args} in 5 minutes."
        self.class.set(wait: 5.minutes + rand(30)).perform_later(*args)
      else
        perform_archive_job(*args)
      end
    end

    private

    def perform_archive_job(_args)
      raise NotImplementedError, "You must override perform_archive_job"
    end

    def currently_running_archive_jobs
      GoodJob::Job.where(job_class: ArchiveBase.subclasses.map(&:to_s))
                  .running
                  .count
    rescue StandardError
      # If code gets to this point and there is no database connection or
      # GoodJob is not available, we're running in a test environment and
      # have not mocked the query, so we're not testing the
      # concurrency-limiting behavior.
      0
    end
  end
end
