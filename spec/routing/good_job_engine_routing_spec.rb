# frozen_string_literal: true

# Regression coverage for the /good_job admin dashboard mount. The Sidekiq
# migration removed /sidekiq; this spec locks in that the replacement mount
# is present in the app's route table. The admin-only warden constraint on
# the mount block is covered by the existing admin auth infrastructure and
# by the fact that /sidekiq (the previous mount) worked the same way.

require "spec_helper"

describe "GoodJob::Engine admin mount", type: :routing do
  it "declares the good_job_path route helper" do
    expect(Rails.application.routes.url_helpers).to respond_to(:good_job_path)
  end

  it "mounts the GoodJob::Engine (not Sidekiq::Web)" do
    mount_paths = Rails.application.routes.routes.map {|r| r.path.spec.to_s }
    expect(mount_paths).to include(a_string_matching(%r{/good_job}))
    expect(mount_paths).not_to include(a_string_matching(%r{/sidekiq}))
  end
end
