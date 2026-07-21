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
    # Under GoodJob concurrency is measured by querying the good_jobs
    # table for rows matching an ArchiveBase subclass with performed_at
    # set and finished_at nil. We stub that query rather than exercise
    # the real ActiveRecord relation.
    before do
      AppConfig.settings.archive_jobs_concurrency = 1
    end

    def stub_running_count(count)
      scope = double("good_job_scope")
      allow(scope).to receive(:where).and_return(scope)
      allow(scope).to receive_message_chain(:where, :not).and_return(scope)
      allow(scope).to receive(:count).and_return(count)
      stub_const("GoodJob::Job", double("GoodJob::Job"))
      allow(GoodJob::Job).to receive(:where).and_return(scope)
    end

    it "schedules a job for later when already another parallel export job is running" do
      stub_running_count(1)

      expect(Workers::ExportUser).to receive(:perform_in).with(kind_of(Numeric), alice.id)
      expect(alice).not_to receive(:perform_export!)

      Workers::ExportUser.new.perform(alice.id)
    end

    it "runs the export when no other job is running" do
      stub_running_count(0)

      expect(Workers::ExportUser).not_to receive(:perform_in).with(kind_of(Numeric), alice.id)
      expect(alice).to receive(:perform_export!)

      Workers::ExportUser.new.perform(alice.id)
    end
  end
end
