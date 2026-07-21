# frozen_string_literal: true

module Workers
  class RecurringPodCheck < Base
    diaspora_queue :low

    def perform
      Pod.check_all!
    end
  end
end
