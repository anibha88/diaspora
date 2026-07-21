# frozen_string_literal: true

# Coverage for the spec/support/inlined_jobs.rb helper.
#
# Four integration specs (receiving_spec, account_migration_spec,
# import_service_spec, mentioning_spec) depend on this helper to run jobs
# synchronously inside a block. The GoodJob migration reimplemented it
# against ActiveJob::TestHelper.perform_enqueued_jobs; this spec pins the
# observable contract: any perform_async issued inside the block executes
# before the block returns, the block's return value is passed through,
# and any jobs enqueued before the helper are cleared out first.

# A minimal Workers::Base subclass that records perform invocations.
# Declared as a real top-level constant so ActiveJob's queue adapters
# (which serialize and then constantize the class name) can round-trip it.
module InlinedJobsSpec
  class RecordingWorker < Workers::Base
    def self.reset!
      @performed_args = []
    end

    def self.performed_args
      @performed_args ||= []
    end

    def perform(*args)
      self.class.performed_args << args
    end
  end
end

describe "inlined_jobs helper", type: :support do
  before do
    InlinedJobsSpec::RecordingWorker.reset!
  end

  it "runs jobs enqueued inside the block before returning" do
    inlined_jobs do
      InlinedJobsSpec::RecordingWorker.perform_async("hello", 1)
    end

    expect(InlinedJobsSpec::RecordingWorker.performed_args).to eq([["hello", 1]])
  end

  it "yields a job-class handle to the block (used by callers that need it)" do
    yielded = nil
    inlined_jobs {|worker_class| yielded = worker_class }

    # The former Sidekiq era yielded Sidekiq::Worker; under ActiveJob the
    # equivalent stand-in is ActiveJob::Base. Callers typically ignore it.
    expect(yielded).to eq(ActiveJob::Base)
  end

  it "returns the block's value" do
    result = inlined_jobs { 42 }
    expect(result).to eq(42)
  end

  it "clears any previously-queued jobs before running the block" do
    # Queue a job outside the helper on the same test adapter it uses;
    # then invoke the helper with an empty block. The pre-existing job
    # must not fire, because clear_enqueued_jobs runs first.
    previous_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    begin
      InlinedJobsSpec::RecordingWorker.perform_async("stale")
    ensure
      ActiveJob::Base.queue_adapter = previous_adapter
    end

    inlined_jobs { nil }

    expect(InlinedJobsSpec::RecordingWorker.performed_args).to be_empty
  end

  it "runs multiple jobs enqueued inside the block" do
    inlined_jobs do
      InlinedJobsSpec::RecordingWorker.perform_async(1)
      InlinedJobsSpec::RecordingWorker.perform_async(2)
      InlinedJobsSpec::RecordingWorker.perform_async(3)
    end

    expect(InlinedJobsSpec::RecordingWorker.performed_args).to match_array([[1], [2], [3]])
  end
end
