# frozen_string_literal: true

module Workers
  class RecheckScheduledPods < Base
    queue_as :low

    def perform
      Pod.check_scheduled!
    end
  end
end
