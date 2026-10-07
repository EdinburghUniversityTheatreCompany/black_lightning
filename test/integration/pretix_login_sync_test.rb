# frozen_string_literal: true

require "application_integration_test"

# Signing in to the pretix shop goes through Doorkeeper's authorization endpoint, the
# only moment we learn a member has a pretix customer. Without this hook a new member
# waits for the nightly reconcile, so these pin that the enqueue happens through the
# real endpoint.
class PretixLoginSyncTest < ApplicationIntegrationTest
  setup do
    @user = FactoryBot.create(:user)
    @application = FactoryBot.create(:doorkeeper_application,
                                    redirect_uri: "https://#{Pretix::Settings::SHOP_HOST}/eutc/account/login/return")
    @token = ENV["PRETIX_API_TOKEN"]
    ENV["PRETIX_API_TOKEN"] = "test-token"
  end

  teardown { ENV["PRETIX_API_TOKEN"] = @token }

  test "authorizing the shop enqueues a delayed membership sync for the signed-in user" do
    # Delayed because pretix creates the customer after we respond.
    freeze_time
    login_as @user

    assert_enqueued_with(job: Pretix::SyncMembershipJob, args: [ @user.id ],
                         at: Pretix::SyncMembershipJob::FIRST_LOGIN_DELAY.from_now) do
      authorize!
    end
  end

  test "signing in to a DIFFERENT oauth client enqueues nothing" do
    # The hook fires for every client the society runs; a sync here is two pointless reads.
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
    # Doorkeeper either auto-approves (302 with a code) or renders consent; only
    # approval fires the hook, so post the consent when asked.
    return unless response.status == 200

    post "/oauth/authorize", params: {
      client_id: application.uid,
      redirect_uri: application.redirect_uri,
      response_type: "code",
      scope: "openid profile email"
    }
  end
end
