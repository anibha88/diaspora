# frozen_string_literal: true

module Workers
  class SendBase < Base
    # send job to the dead job queue
    class MaxRetriesReached < RuntimeError
    end

    diaspora_queue :medium

    # SendBase manages its own retries (via schedule_retry + perform_in), so the
    # framework must NOT auto-retry (this mirrors the former `retry: 0`).
    # `attempts: 1` means "run once, never retry". Once the sender gives up it
    # raises MaxRetriesReached, which we discard rather than retry (the former
    # "send to the dead job queue" behavior).
    retry_on StandardError, attempts: 1
    discard_on MaxRetriesReached

    MAX_RETRIES = (rt = AppConfig.environment.workers.retry.get) ? rt.to_i : 10

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
  end
end
