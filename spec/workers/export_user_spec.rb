# frozen_string_literal: true

describe Workers::ExportUser do
  before do
    allow(User).to receive(:find).with(alice.id).and_return(alice)
  end

  it 'calls export! on user with given id' do
    expect(alice).to receive(:perform_export!)
    Workers::ExportUser.new.perform(alice.id)
  end

  it 'sends a success message when the export is successful' do
    allow(alice).to receive(:export).and_return(OpenStruct.new)
    expect(ExportMailer).to receive(:export_complete_for).with(alice).and_call_original
    Workers::ExportUser.new.perform(alice.id)
  end

  it 'sends a failure message when the export fails' do
    allow(alice).to receive(:export).and_return(nil)
    expect(alice).to receive(:perform_export!).and_return(false)
    expect(ExportMailer).to receive(:export_failure_for).with(alice).and_call_original
    Workers::ExportUser.new.perform(alice.id)
  end

  context "concurrency" do
    before do
      AppConfig.settings.archive_jobs_concurrency = 1
    end

    # Stub GoodJob::Job.where(...).where.not(...).count to return `count`, and
    # GoodJob::Job.where(...).count (no exclusion, when current job has no id)
    # to return the same. Mirrors what ArchiveBase#currently_running_archive_jobs
    # queries against the good_jobs table.
    def stub_running_archive_jobs(count)
      chain = double("scope")
      allow(chain).to receive(:where).and_return(chain)
      allow(chain).to receive_message_chain(:where, :not).and_return(chain)
      allow(chain).to receive(:count).and_return(count)
      stub_const("GoodJob::Job", double("GoodJob::Job")) unless defined?(GoodJob::Job)
      allow(GoodJob::Job).to receive(:where).and_return(chain)
    end

    it "schedules a job for later when already another parallel export job is running" do
      stub_running_archive_jobs(1)

      expect(Workers::ExportUser).to receive(:perform_in).with(kind_of(Numeric), alice.id)
      expect(alice).not_to receive(:perform_export!)

      Workers::ExportUser.new.perform(alice.id)
    end

    it "runs the export when the current job is the only one in flight" do
      # When the current job excludes itself, the visible count is 0.
      stub_running_archive_jobs(0)

      expect(Workers::ExportUser).not_to receive(:perform_in).with(kind_of(Numeric), alice.id)
      expect(alice).to receive(:perform_export!)

      Workers::ExportUser.new.perform(alice.id)
    end

    it "runs the export when no other job is running" do
      stub_running_archive_jobs(0)

      expect(Workers::ExportUser).not_to receive(:perform_in).with(kind_of(Numeric), alice.id)
      expect(alice).to receive(:perform_export!)

      Workers::ExportUser.new.perform(alice.id)
    end

    it "runs the export when a non-archive job is running (unrelated class)" do
      # ArchiveBase.subclasses filters the where(job_class:) query, so unrelated
      # jobs are never counted — expressed here as a zero-return stub.
      stub_running_archive_jobs(0)

      expect(Workers::ExportUser).not_to receive(:perform_in).with(kind_of(Numeric), alice.id)
      expect(alice).to receive(:perform_export!)

      Workers::ExportUser.new.perform(alice.id)
    end
  end
end
