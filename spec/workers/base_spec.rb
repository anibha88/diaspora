# frozen_string_literal: true

# Characterization spec for Workers::Base.
#
# Post-migration Workers::Base is an ActiveJob (via ApplicationJob) running
# on GoodJob. The class exposes a Sidekiq-shaped compatibility API
# (perform_async / perform_in / perform_at + a sidekiq_options DSL) so the
# ~40 call sites in models/controllers/services continue to work
# unchanged.

describe Workers::Base do
  describe "worker interface" do
    it "inherits from ApplicationJob (ActiveJob) so it runs on GoodJob" do
      expect(Workers::Base.ancestors).to include(ApplicationJob, ActiveJob::Base)
    end

    it "responds to the class-level enqueue methods used across the app" do
      expect(Workers::Base).to respond_to(:perform_async)
      expect(Workers::Base).to respond_to(:perform_in)
      expect(Workers::Base).to respond_to(:perform_at)
      expect(Workers::Base).to respond_to(:perform_later)
    end

    it "mixes in Diaspora::Logging" do
      expect(Workers::Base.included_modules).to include(Diaspora::Logging)
    end
  end

  describe "retry / backtrace configuration (via AppConfig)" do
    it "reads its default retry count from the good_job AppConfig section" do
      expected_retry = AppConfig.environment.good_job.retry.get.to_i
      expect(Workers::Base::DEFAULT_RETRIES).to eq(expected_retry)
    end

    it "exposes those values through the legacy sidekiq_options hash" do
      opts = Workers::Base.sidekiq_options
      expect(opts["retry"]).to     eq(AppConfig.environment.good_job.retry.get.to_i)
      expect(opts["backtrace"]).to eq(AppConfig.environment.good_job.backtrace.get.to_i)
    end
  end

  describe "queue assignment on subclasses" do
    # Locks in the queue -> worker mapping documented in the (deleted)
    # config/sidekiq.yml. A migration typo (e.g. queue_as :default instead
    # of :urgent) shows up here before it ever hits federation.
    {
      Workers::ReceivePublic         => "urgent",
      Workers::ReceivePrivate        => "urgent",
      Workers::ReceiveLocal          => "high",
      Workers::DeferredDispatch      => "high",
      Workers::SendPublic            => "medium",
      Workers::SendPrivate           => "medium",
      Workers::GatherOEmbedData      => "medium",
      Workers::GatherOpenGraphData   => "medium",
      Workers::ExportUser            => "low",
      Workers::ExportPhotos          => "low",
      Workers::ProcessPhoto          => "low",
      Workers::DeleteAccount         => "low",
      Workers::QueueUsersForRemoval  => "low",
      Workers::Mail::ConfirmEmail    => "low"
    }.each do |worker_class, expected_queue|
      it "enqueues #{worker_class} on the #{expected_queue} queue" do
        expect(worker_class.queue_name.to_s).to eq(expected_queue)
      end
    end
  end

  describe "class API compatibility (used at ~40 call sites)" do
    # We only assert that these class methods exist and accept the shapes
    # used in production. Whether they enqueue via inline execution or via
    # GoodJob's DB queue depends on the current adapter; that behaviour
    # is covered by spec/inlined_jobs_spec.rb and per-worker specs.
    let(:dummy_worker) do
      Class.new(Workers::Base) do
        def self.name
          "Workers::BaseSpec::Dummy"
        end

        def perform(*); end
      end
    end

    before do
      # Route enqueues to the ActiveJob test adapter so we can assert on
      # shape without touching the database or the GoodJob adapter's
      # inline mode (which would try to actually run the job).
      @previous_adapter = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      stub_const("Workers::BaseSpec::Dummy", dummy_worker)
    end

    after { ActiveJob::Base.queue_adapter = @previous_adapter }

    it "accepts perform_async with positional arguments" do
      expect { dummy_worker.perform_async(1, "two", {three: 3}) }.not_to raise_error
    end

    it "accepts perform_in with an interval and positional arguments" do
      expect { dummy_worker.perform_in(5.minutes, 1, "two") }.not_to raise_error
    end

    it "accepts perform_at with an absolute time and positional arguments" do
      expect { dummy_worker.perform_at(1.hour.from_now, 1) }.not_to raise_error
    end
  end
end
