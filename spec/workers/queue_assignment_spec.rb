# frozen_string_literal: true

#   Copyright (c) 2010-2011, Diaspora Inc.  This file is
#   licensed under the Affero General Public License version 3 or later.  See
#   the COPYRIGHT file.

# Regression spec: pins down the queue each worker runs on and the queue
# priority order across the Sidekiq -> GoodJob migration. Queue names and numeric
# priorities are read off a job instance so inherited declarations (from
# Base/SendBase/ReceiveBase/ArchiveBase/NotifierBase) are covered, not just the
# ones with an explicit diaspora_queue line.

describe "Worker queue assignment" do
  # worker class => expected effective queue name
  expected_queues = {
    # urgent
    Workers::ReceiveBase             => "urgent",
    Workers::ReceivePublic           => "urgent",
    Workers::ReceivePrivate          => "urgent",
    Workers::ResetPassword           => "urgent",
    Workers::FetchWebfinger          => "urgent",

    # high
    Workers::ReceiveLocal            => "high",
    Workers::DeferredDispatch        => "high",
    Workers::DeferredRetraction      => "high",

    # medium
    Workers::SendBase                => "medium",
    Workers::SendPublic              => "medium",
    Workers::SendPrivate             => "medium",
    Workers::GatherOEmbedData        => "medium",
    Workers::GatherOpenGraphData     => "medium",
    Workers::FetchPublicPosts        => "medium",

    # low (incl. everything inheriting from ArchiveBase / NotifierBase)
    Workers::ArchiveBase             => "low",
    Workers::ExportUser              => "low",
    Workers::ImportUser              => "low",
    Workers::ExportPhotos            => "low",
    Workers::ProcessPhoto            => "low",
    Workers::DeleteAccount           => "low",
    Workers::RemoveOldUser           => "low",
    Workers::QueueUsersForRemoval    => "low",
    Workers::CheckBirthday           => "low",
    Workers::CleanCachedFiles        => "low",
    Workers::CleanupOldExports       => "low",
    Workers::CleanupPendingPhotos    => "low",
    Workers::RecurringPodCheck       => "low",
    Workers::RecheckScheduledPods    => "low",

    # mail workers inherit :low from Workers::Mail::NotifierBase
    Workers::Mail::NotifierBase      => "low",
    Workers::Mail::AlsoCommented     => "low",
    Workers::Mail::CommentOnPost     => "low",
    Workers::Mail::ConfirmEmail      => "low",
    Workers::Mail::ContactsBirthday  => "low",
    Workers::Mail::CsrfTokenFail     => "low",
    Workers::Mail::InviteEmail       => "low",
    Workers::Mail::Liked             => "low",
    Workers::Mail::LikedComment      => "low",
    Workers::Mail::Mentioned         => "low",
    Workers::Mail::MentionedInComment => "low",
    Workers::Mail::PrivateMessage    => "low",
    Workers::Mail::ReportWorker      => "low",
    Workers::Mail::Reshared          => "low",
    Workers::Mail::StartedSharing    => "low"
  }

  expected_queues.each do |worker, queue|
    it "assigns #{worker} to the '#{queue}' queue with the matching priority" do
      instance = worker.new

      expect(instance.queue_name.to_s).to eq(queue)
      expect(instance.priority).to eq(Workers::Base::QUEUE_PRIORITIES.fetch(queue.to_sym))
    end
  end

  describe "queue priority order" do
    # GoodJob is configured with smaller_number_is_higher_priority, so lower
    # numbers run first. The numeric priorities must keep the queues in the same
    # strict order Sidekiq drained them.
    it "orders the queues from highest to lowest priority" do
      ordered = Workers::Base::QUEUE_PRIORITIES.sort_by {|_name, priority| priority }.map(&:first)

      expect(ordered).to eq(%i[urgent high medium low default])
    end
  end
end
