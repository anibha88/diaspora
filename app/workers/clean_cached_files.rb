# frozen_string_literal: true

module Workers
  class CleanCachedFiles < Base
    queue_as :low

    def perform
      CarrierWave.clean_cached_files!
    end
  end
end
