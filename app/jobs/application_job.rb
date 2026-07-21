# frozen_string_literal: true

# Top-level base class for every ActiveJob (and therefore every worker) in the
# app. Sits between ActiveJob::Base and Workers::Base so future cross-cutting
# concerns (queue naming defaults, callbacks, argument serializers) have a
# single obvious home.
class ApplicationJob < ActiveJob::Base
end
