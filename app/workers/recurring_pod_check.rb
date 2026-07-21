# frozen_string_literal: true

module Workers
  class RecurringPodCheck < Base
    queue_as :low

    def perform
      Pod.check_all!
    end
  end
end
