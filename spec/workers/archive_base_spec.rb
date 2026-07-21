# frozen_string_literal: true

# Characterization spec for Workers::ArchiveBase concurrency throttling.
#
# Under Sidekiq this counted in-flight jobs via Sidekiq::Workers.new;
# under GoodJob it queries the good_jobs table for rows whose job_class
# is an ArchiveBase subclass and that have been performed but not
# finished (excluding the current job).

describe Workers::ArchiveBase do
  let(:worker_class) do
    Class.new(Workers::ArchiveBase) do
      def self.name
        "Workers::ArchiveBaseSpec::DummyArchiveWorker"
      end

      def perform_archive_job(*args)
        # no-op; specs assert on this via message expectations
      end
    end
  end

  # Stand-in for the GoodJob::Job ActiveRecord relation. Only the methods
  # actually chained by ArchiveBase are stubbed.
  let(:empty_scope) { double("scope", where: nil, count: 0) }

  before do
    AppConfig.settings.archive_jobs_concurrency = 1
    stub_const(worker_class.name, worker_class)
    allow(Workers::ArchiveBase).to receive(:subclasses).and_return([worker_class])
  end

  # Small helper: return a scope-like double that reports `count`
  # in-flight archive jobs. The chained `.where.not.where.not` calls
  # inside currently_running_archive_jobs each return the same double.
  def stub_running_count(count)
    scope = double("good_job_scope")
    allow(scope).to receive(:where).and_return(scope)
    allow(scope).to receive_message_chain(:where, :not).and_return(scope)
    allow(scope).to receive(:count).and_return(count)
    stub_const("GoodJob::Job", double("GoodJob::Job"))
    allow(GoodJob::Job).to receive(:where).and_return(scope)
    scope
  end

  describe "#perform" do
    context "when the concurrency limit has not been reached" do
      it "runs perform_archive_job with the provided args" do
        stub_running_count(0)

        worker = worker_class.new
        expect(worker).to receive(:perform_archive_job).with(42, "hello")
        expect(worker_class).not_to receive(:perform_in)

        worker.perform(42, "hello")
      end

      it "returns zero (below the limit) when no ArchiveBase subclasses exist" do
        allow(Workers::ArchiveBase).to receive(:subclasses).and_return([])

        worker = worker_class.new
        expect(worker).to receive(:perform_archive_job).with(42)
        worker.perform(42)
      end
    end

    context "when the concurrency limit has been reached" do
      it "reschedules itself ~5 minutes out with the same args" do
        stub_running_count(1)

        worker = worker_class.new
        expect(worker).not_to receive(:perform_archive_job)
        expect(worker_class).to receive(:perform_in) do |delay, *args|
          expect(delay).to be_between(5.minutes, 5.minutes + 30.seconds)
          expect(args).to eq([42, "hello"])
        end

        worker.perform(42, "hello")
      end
    end

    context "when the good_jobs table is unreachable (test env / not migrated)" do
      it "treats the running-job count as zero and proceeds with the work" do
        stub_const("GoodJob::Job", double("GoodJob::Job"))
        allow(GoodJob::Job).to receive(:where).and_raise(
          ActiveRecord::StatementInvalid, "relation \"good_jobs\" does not exist"
        )

        worker = worker_class.new
        expect(worker).to receive(:perform_archive_job).with(42)
        expect(worker_class).not_to receive(:perform_in)

        worker.perform(42)
      end
    end
  end

  describe "#perform_archive_job" do
    it "raises NotImplementedError by default so subclasses must override it" do
      expect { Workers::ArchiveBase.new.send(:perform_archive_job, 42) }
        .to raise_error(NotImplementedError, /perform_archive_job/)
    end
  end
end
