# frozen_string_literal: true

require "test_helper"

class Pretix::SyncMembershipJobTest < ActiveJob::TestCase
  # No mocking library in this suite, so the sync is a hand-written stand-in
  # injected through the job's builder seam.
  class RecordingSync
    attr_reader :synced

    def initialize(raise_with: nil)
      @raise_with = raise_with
      @synced = []
    end

    def sync_user(user)
      raise @raise_with if @raise_with

      @synced << user.id
      :created
    end
  end

  setup do
    @user = FactoryBot.create(:user)
    @token = ENV["PRETIX_API_TOKEN"]
    ENV["PRETIX_API_TOKEN"] = "test-token"
  end

  teardown do
    ENV["PRETIX_API_TOKEN"] = @token
    Pretix::SyncMembershipJob.sync_builder = -> { Pretix::MembershipSync.new }
  end

  test "enqueue_for de-duplicates and drops blanks" do
    assert_enqueued_jobs 1, only: Pretix::SyncMembershipJob do
      Pretix::SyncMembershipJob.enqueue_for([ @user.id, @user.id, nil ])
    end
  end

  test "enqueue_for does nothing when pretix is not configured" do
    ENV["PRETIX_API_TOKEN"] = nil

    assert_no_enqueued_jobs only: Pretix::SyncMembershipJob do
      Pretix::SyncMembershipJob.enqueue_for([ @user.id ])
    end
  end

  test "syncs the user it was given" do
    sync = with_sync(RecordingSync.new)

    Pretix::SyncMembershipJob.perform_now(@user.id)

    assert_equal [ @user.id ], sync.synced
  end

  test "a deleted user is a no-op rather than an error" do
    sync = with_sync(RecordingSync.new)
    id = @user.id
    @user.destroy!

    assert_nothing_raised { Pretix::SyncMembershipJob.perform_now(id) }
    assert_empty sync.synced
  end

  test "a pretix failure is swallowed, because the nightly reconcile is the safety net" do
    # Retrying here would re-hit a shop that is already failing, for a person
    # tonight's reconcile fixes anyway. See the job's class comment.
    with_sync(RecordingSync.new(raise_with: Pretix::Client::Error.new("boom")))

    assert_nothing_raised { Pretix::SyncMembershipJob.perform_now(@user.id) }
  end

  private

  def with_sync(sync)
    Pretix::SyncMembershipJob.sync_builder = -> { sync }
    sync
  end
end
