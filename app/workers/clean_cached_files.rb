# frozen_string_literal: true

module Workers
  class CleanCachedFiles < Base
    diaspora_queue :low

    def perform
      CarrierWave.clean_cached_files!
    end
  end
end
