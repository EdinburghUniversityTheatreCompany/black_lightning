# frozen_string_literal: true

require "application_integration_test"

##
# Signing in to the pretix shop runs through Doorkeeper's authorization
# endpoint, and that is the ONLY moment we learn a member has a pretix customer
# account at all — pretix creates one on first login and offers no webhook to
# say so. Without this hook a new member waits for the nightly reconcile, so
# these tests pin that the enqueue actually happens through the real endpoint
# rather than through my reading of Doorkeeper's API.
class PretixLoginSyncTest < ApplicationIntegrationTest
  setup do
    @user = FactoryBot.create(:user)
    @application = FactoryBot.create(:doorkeeper_application,
                                    redirect_uri: "https://#{Pretix::Settings::SHOP_HOST}/eutc/account/login/return")
    @token = ENV["PRETIX_API_TOKEN"]
    ENV["PRETIX_API_TOKEN"] = "test-token"
  end

  teardown { ENV["PRETIX_API_TOKEN"] = @token }

  test "authorizing the shop enqueues a membership sync for the signed-in user" do
    login_as @user

    assert_enqueued_with(job: Pretix::SyncMembershipJob, args: [ @user.id ]) do
      authorize!
    end
  end

  test "the sync is delayed, because pretix creates the customer after we respond" do
    login_as @user

    assert_enqueued_jobs 1, only: Pretix::SyncMembershipJob do
      authorize!
    end

    enqueued = enqueued_jobs.find { |job| job["job_class"] == Pretix::SyncMembershipJob.name }
    scheduled_at = enqueued["scheduled_at"]
    assert scheduled_at.present?, "a first login finds no customer yet, so the sync must be deferred"
    assert_operator Time.zone.parse(scheduled_at.to_s), :>, Time.current
  end

  test "signing in to a DIFFERENT oauth client enqueues nothing" do
    # after_successful_authorization fires for every client the society runs, and
    # a sync for someone signing in elsewhere is two pointless pretix API reads.
    other = FactoryBot.create(:doorkeeper_application, redirect_uri: "https://example.com/callback")
    login_as @user

    assert_no_enqueued_jobs only: Pretix::SyncMembershipJob do
      authorize!(other)
    end
  end

  test "nothing is enqueued when pretix is not configured" do
    ENV["PRETIX_API_TOKEN"] = nil
    login_as @user

    assert_no_enqueued_jobs only: Pretix::SyncMembershipJob do
      authorize!
    end
  end

  private

  def authorize!(application = @application)
    get "/oauth/authorize", params: {
      client_id: application.uid,
      redirect_uri: application.redirect_uri,
      response_type: "code",
      scope: "openid profile email"
    }
    # Doorkeeper either auto-approves (302 with a code) or renders consent.
    # Only the approving path fires after_successful_authorization, so post the
    # consent when it asks for one.
    return unless response.status == 200

    post "/oauth/authorize", params: {
      client_id: application.uid,
      redirect_uri: application.redirect_uri,
      response_type: "code",
      scope: "openid profile email"
    }
  end
end
