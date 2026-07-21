# frozen_string_literal: true

module Workers
  class SendBase < Base
    queue_as :medium

    # Custom retry loop: SendBase reschedules itself via perform_in with an
    # explicit exponential backoff (see #seconds_to_delay). We do NOT want
    # ActiveJob's built-in retry mechanism to also retry on top of that, so
    # override the retry policy installed by Workers::Base to a single attempt.
    retry_on StandardError, attempts: 1

    MAX_RETRIES = AppConfig.environment.good_job.retry.get.to_i

    protected

    def schedule_retry(retry_count, sender_id, obj_str, failed_urls)
      if retry_count < (obj_str.start_with?("Contact") ? MAX_RETRIES + 10 : MAX_RETRIES)
        yield(seconds_to_delay(retry_count), retry_count)
      else
        logger.warn "status=abandon sender=#{sender_id} obj=#{obj_str} failed_urls='[#{failed_urls.join(', ')}]'"
        raise MaxRetriesReached
      end
    end

    private

    # based on Sidekiq::Middleware::Server::RetryJobs#seconds_to_delay
    def seconds_to_delay(count)
      ((count + 3)**4) + (rand(30) * (count + 1))
    end

    # send job to the discarded/preserved set
    class MaxRetriesReached < RuntimeError
    end
  end
end
