# frozen_string_literal: true

#   Copyright (c) 2010-2011, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

# Regression spec: pins down how ArchiveBase limits the number of concurrently
# running archive jobs across the Sidekiq -> GoodJob migration. The count of
# running archive jobs now comes from a GoodJob::Job query (formerly
# Sidekiq::Workers introspection); the observable behavior is unchanged:
# over the limit -> reschedule via perform_in, otherwise run.
#
# The concurrency behavior is also exercised through Workers::ExportUser in
# spec/workers/export_user_spec.rb; here we characterize the ArchiveBase logic
# directly via a throwaway subclass.

describe Workers::ArchiveBase do
  # A minimal ArchiveBase subclass so we test the base concurrency logic itself,
  # independent of any real archive worker's side effects.
  let(:worker_class) do
    Class.new(described_class) do
      def self.name
        "Workers::TestArchiveJob"
      end

      def self.to_s
        name
      end

      def perform_archive_job(*); end
    end
  end

  before do
    AppConfig.settings.archive_jobs_concurrency = 1
  end

  # Stub the running-jobs count that currently_running_archive_jobs computes
  # from GoodJob::Job.
  def stub_running_archive_jobs(count)
    allow_any_instance_of(worker_class).to receive(:currently_running_archive_jobs).and_return(count)
  end

  context "when another archive job is already running" do
    it "reschedules instead of running the job" do
      stub_running_archive_jobs(1)

      expect(worker_class).to receive(:perform_in).with(kind_of(Integer), 42)
      expect_any_instance_of(worker_class).not_to receive(:perform_archive_job)

      worker_class.new.perform(42)
    end
  end

  context "when the number of running jobs is below the limit" do
    it "runs the job" do
      stub_running_archive_jobs(0)

      expect(worker_class).not_to receive(:perform_in)
      expect_any_instance_of(worker_class).to receive(:perform_archive_job).with(42)

      worker_class.new.perform(42)
    end
  end
end
