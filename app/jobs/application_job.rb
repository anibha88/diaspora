# frozen_string_literal: true

# Base ActiveJob for the whole application. Concrete jobs continue to live
# under Workers:: (see app/workers/), inherit from Workers::Base, and thus
# transitively from ApplicationJob. This exists mainly so we have a single
# place to hang cross-cutting ActiveJob configuration if we ever need it.
class ApplicationJob < ActiveJob::Base
end
