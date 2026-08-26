# frozen_string_literal: true

require "test_helper"

##
# Role#archive is the annual de-membering of the whole society, and it removes
# people with users.clear — delete_all, which fires NO association callbacks. So
# nothing observes it the way add_role is observed, and it needs the explicit
# enqueue these tests pin. See docs/pretix/membership-sync.md.
class RolePretixSyncTest < ActiveSupport::TestCase
  setup do
    @token = ENV["PRETIX_API_TOKEN"]
    ENV["PRETIX_API_TOKEN"] = "test-token"
    @member_role = Role.find_or_create_by!(name: "member")
    @user = FactoryBot.create(:user)
    @user.add_role :member
  end

  teardown { ENV["PRETIX_API_TOKEN"] = @token }

  test "archiving the member role enqueues a sync for everyone who held it" do
    assert_enqueued_with(job: Pretix::SyncMembershipJob, args: [ @user.id ]) do
      @member_role.reload.archive("25/26")
    end
  end

  test "archive still reports success to its caller" do
    # Admin::RolesController branches on the return value, so the added enqueue
    # must not become the method's result.
    assert @member_role.reload.archive("25/26"), "archive must stay truthy"
  end

  test "archiving a role that grants no member pricing enqueues nothing" do
    trained = Role.find_or_create_by!(name: "DM Trained")
    @user.add_role "DM Trained"

    assert_no_enqueued_jobs only: Pretix::SyncMembershipJob do
      trained.reload.archive("25/26")
    end
  end

  test "the user really has lost the role, so the sync will expire them" do
    @member_role.reload.archive("25/26")

    assert_not @user.reload.has_role?(:member)
    assert_not Pretix::MembershipSync.entitled?(@user.reload)
  end
end
