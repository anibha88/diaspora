# frozen_string_literal: true

module Workers
  module Mail
    class NotifierBase < Base
      diaspora_queue :low

      def perform(*args)
        Notifier.send_notification(self.class.name.demodulize.underscore, *args).deliver_now
      end
    end
  end
end
