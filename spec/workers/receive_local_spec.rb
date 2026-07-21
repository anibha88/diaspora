# frozen_string_literal: true

# Direct .perform coverage for Workers::ReceiveLocal.
#
# ReceiveLocal is the federation-critical worker that fans an inbound
# object out to its local recipients, then triggers notifications. Before
# this spec its behaviour was only exercised through mocked enqueue
# expectations in spec/federation_callbacks_spec.rb; the perform body
# itself was uncovered. Given the Sidekiq -> GoodJob migration touches
# this worker's base class, we characterize the four branches here.

describe Workers::ReceiveLocal do
  let(:object_id)          { 42 }
  let(:recipient_user_ids) { [1, 2, 3] }
  let(:notification_service) { instance_double(NotificationService) }

  before do
    allow(NotificationService).to receive(:new).and_return(notification_service)
    allow(notification_service).to receive(:notify)
  end

  context "when the target object responds to :receive" do
    let(:object) { instance_double(StatusMessage) }

    before do
      allow(object).to receive(:respond_to?).with(:receive).and_return(true)
      allow(StatusMessage).to receive(:find).with(object_id).and_return(object)
    end

    it "invokes #receive with the recipient user ids" do
      expect(object).to receive(:receive).with(recipient_user_ids)

      Workers::ReceiveLocal.new.perform("StatusMessage", object_id, recipient_user_ids)
    end

    it "notifies via NotificationService with the object and recipients" do
      allow(object).to receive(:receive)
      expect(notification_service).to receive(:notify).with(object, recipient_user_ids)

      Workers::ReceiveLocal.new.perform("StatusMessage", object_id, recipient_user_ids)
    end
  end

  context "when the target object does not respond to :receive" do
    # e.g. a Person record — no local fan-out, but notifications still run.
    # We use a bare `double` (not an `instance_double(Person)`) here on
    # purpose: instance_double refuses negative expectations on methods
    # the real class doesn't define, and #receive is exactly one such
    # method on Person. The behaviour we want to lock down is that
    # ReceiveLocal calls NotificationService anyway; if it wrongly tried
    # to call #receive on the double, the double would raise NoMethodError
    # and NotificationService would never fire — so a single positive
    # expectation is enough.
    let(:object) do
      double("Person", respond_to?: false).tap do |o|
        allow(o).to receive(:respond_to?).with(:receive).and_return(false)
      end
    end

    before do
      allow(Person).to receive(:find).with(object_id).and_return(object)
    end

    it "still notifies via NotificationService (and does not touch #receive)" do
      expect(notification_service).to receive(:notify).with(object, recipient_user_ids)

      Workers::ReceiveLocal.new.perform("Person", object_id, recipient_user_ids)
    end
  end

  context "when the object has already been deleted before the job runs" do
    it "swallows ActiveRecord::RecordNotFound instead of retrying" do
      allow(StatusMessage).to receive(:find)
        .with(object_id).and_raise(ActiveRecord::RecordNotFound)

      expect {
        Workers::ReceiveLocal.new.perform("StatusMessage", object_id, recipient_user_ids)
      }.not_to raise_error

      expect(notification_service).not_to have_received(:notify)
    end
  end
end
