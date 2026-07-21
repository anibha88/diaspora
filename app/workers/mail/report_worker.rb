# frozen_string_literal: true

module Workers
  module Mail
    class ReportWorker < Base
      diaspora_queue :low

      def perform(report_id)
        ReportMailer.new_report(report_id).each(&:deliver_now)
      end
    end
  end
end
