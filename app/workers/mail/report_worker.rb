# frozen_string_literal: true

module Workers
  module Mail
    class ReportWorker < Base
      queue_as :low

      def perform(report_id)
        ReportMailer.new_report(report_id).each(&:deliver_now)
      end
    end
  end
end
