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

    it "schedules a job for later when already another parallel export job is running" do
      allow_any_instance_of(Workers::ExportUser).to receive(:currently_running_archive_jobs).and_return(1)

      expect(Workers::ExportUser).to receive(:perform_in).with(kind_of(Integer), alice.id)
      expect(alice).not_to receive(:perform_export!)

      Workers::ExportUser.new.perform(alice.id)
    end

    it "runs the export when the number of running jobs is below the limit" do
      allow_any_instance_of(Workers::ExportUser).to receive(:currently_running_archive_jobs).and_return(0)

      expect(Workers::ExportUser).not_to receive(:perform_in).with(kind_of(Integer), alice.id)
      expect(alice).to receive(:perform_export!)

      Workers::ExportUser.new.perform(alice.id)
    end
  end
end
