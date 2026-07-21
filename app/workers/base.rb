# frozen_string_literal: true

#   Copyright (c) 2010-2011, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

module Workers
  class Base < ActiveJob::Base
    queue_as :default

    retry_on StandardError,
             wait:     :exponentially_longer,
             attempts: ((rt = AppConfig.environment.sidekiq.retry.get) ? rt.to_i + 1 : 11)

    include Diaspora::Logging
  end
end
