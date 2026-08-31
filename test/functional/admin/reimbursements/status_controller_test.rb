require "test_helper"

module Admin
  module Reimbursements
    ##
    # The finance-gated integration status dashboard: a page showing the last
    # nightly-run date per cost centre (a plain DB read, always shown) plus
    # on-demand OK/fail/skip probes of Microsoft Graph.
    class StatusControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      # Enable the integration secrets Settings reads (env wins over credentials),
      # restoring the prior values afterwards. Without these Graph sits at its
      # test-env default of "not configured".
      GRAPH_ENV = {
        "REIMBURSEMENTS_AZURE_TENANT_ID" => "tenant",
        "REIMBURSEMENTS_AZURE_CLIENT_ID" => "client",
        "REIMBURSEMENTS_AZURE_CLIENT_SECRET" => "secret"
      }.freeze

      def with_env(vars)
        original = vars.keys.index_with { |key| ENV[key] }
        vars.each { |key, value| ENV[key] = value }
        yield
      ensure
        original.each { |key, value| ENV[key] = value }
      end

      # Fake Graph client for the reachability probe: returns true, or raises to
      # stand in for expired Azure credentials.
      class FakeGraph
        def initialize(ok: true)
          @ok = ok
        end

        def check_reachable
          raise ::GraphAuth::AuthError, "Graph rejected the token (401)" unless @ok

          true
        end
      end

      setup do
        grant_finance_permission(users(:member))
        @user = users(:member)
        @cost_centre = ::Reimbursements::CostCentre.default

        StatusController.graph_builder = -> { FakeGraph.new }
      end

      teardown do
        StatusController.graph_builder = -> { ::Reimbursements::GraphClient.new }
      end

      # --- Auth gating -------------------------------------------------------

      test "requires sign-in" do
        get :show
        assert_redirected_to new_user_session_path
      end

      test "denies members without the finance permission" do
        sign_in users(:committee)
        get :show
        assert_response :forbidden
      end

      test "the producer portal permission alone does not grant finance access" do
        other = users(:member_with_phone_number)
        grant_producer_permission(other)
        sign_in other

        get :show

        assert_response :forbidden
      end

      test "run denies members without the finance permission" do
        sign_in users(:committee)
        post :run
        assert_response :forbidden
      end

      # --- Show (gated render, no live calls) --------------------------------

      test "show renders the dashboard for a finance user" do
        sign_in @user
        get :show

        assert_response :success
        assert_includes response.body, "Integration checks"
        assert_includes response.body, "Run checks"
        # The page itself runs no probes.
        assert_nil assigns(:checks)
      end

      test "show renders the last nightly-run date per cost centre" do
        @cost_centre.update!(last_nightly_run_on: Date.new(2026, 6, 30))
        sign_in @user

        get :show

        assert_response :success
        assert_includes response.body, @cost_centre.name
        assert_includes response.body, "2026-06-30"
      end

      test "show shows a never-run cost centre as such" do
        @cost_centre.update!(last_nightly_run_on: nil)
        sign_in @user

        get :show

        assert_response :success
        assert_includes response.body, "Never"
      end

      # --- Run (on-demand probes) --------------------------------------------

      test "run reports every integration OK when the probes succeed" do
        sign_in @user

        with_env(GRAPH_ENV) { post :run }

        assert_response :success
        assert_includes response.body, "Microsoft Graph"
        assert_includes response.body, "acquired an app token"
      end

      test "run flags Microsoft Graph with the error message when the token probe raises" do
        StatusController.graph_builder = -> { FakeGraph.new(ok: false) }
        sign_in @user

        with_env(GRAPH_ENV) { post :run }

        assert_response :success
        assert_includes response.body, "Graph rejected the token (401)"
        # Points a non-technical finance user at IT to rotate the server credential.
        assert_includes response.body, "Contact IT"
      end

      test "run skips Graph when the Azure credentials are absent" do
        sign_in @user

        # Azure env deliberately unset (the test-env default).
        post :run

        assert_response :success
        assert_includes response.body, "No Azure credentials configured yet"
      end

      test "run still shows the last nightly-run date alongside the probe results" do
        @cost_centre.update!(last_nightly_run_on: Date.new(2026, 6, 30))
        sign_in @user

        with_env(GRAPH_ENV) { post :run }

        assert_response :success
        assert_includes response.body, "2026-06-30"
      end

      # --- Notification recipients ------------------------------------------

      test "flags a cost centre whose notification role has no members" do
        ::Reimbursements::CostCentre.default.notification_role.users.clear
        sign_in @user

        get :show

        assert_response :success
        assert_includes response.body, "No notification recipients"
      end

      test "does not flag a cost centre whose notification role has members" do
        @cost_centre.notification_role.users << users(:member)
        sign_in @user

        get :show

        assert_response :success
        assert_not_includes response.body, "No notification recipients"
      end

      # users(:committee) is the file's stand-in for someone without the finance
      # permission (see the gating tests above); users(:member) can't play that
      # part here because setup grants it that very permission.
      test "flags a notification-role member who lacks the finance permission" do
        @cost_centre.notification_role.users << users(:committee)
        sign_in @user

        get :show

        assert_response :success
        assert_includes response.body, "cannot open the finance screens"
        assert_includes response.body, users(:committee).full_name
      end

      test "does not flag a notification-role member who holds the finance permission" do
        @cost_centre.notification_role.users << users(:member)
        sign_in @user

        get :show

        assert_response :success
        assert_not_includes response.body, "cannot open the finance screens"
      end

      test "run answers a turbo stream that updates the results in place" do
        sign_in @user

        with_env(GRAPH_ENV) { post :run, as: :turbo_stream }

        assert_response :success
        assert_includes response.media_type, "turbo-stream"
        assert_includes response.body, "integration_check_results"
      end
    end
  end
end
