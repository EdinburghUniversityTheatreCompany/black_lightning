require "test_helper"

module Admin
  module Reimbursements
    ##
    # The finance-gated integration status dashboard: a page showing the last
    # nightly-run date per cost centre (a plain DB read, always shown) plus
    # on-demand OK/fail/skip probes of Airtable, Microsoft Graph and Gemini.
    class StatusControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      # Enable the integration secrets Settings reads (env wins over credentials),
      # restoring the prior values afterwards. Without these Airtable/Graph/Gemini
      # sit at their test-env default of "not configured".
      GRAPH_ENV = {
        "REIMBURSEMENTS_AZURE_TENANT_ID" => "tenant",
        "REIMBURSEMENTS_AZURE_CLIENT_ID" => "client",
        "REIMBURSEMENTS_AZURE_CLIENT_SECRET" => "secret"
      }.freeze
      GEMINI_ENV = { "REIMBURSEMENTS_GEMINI_API_KEY" => "a-key" }.freeze

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
          raise ::Reimbursements::GraphAuth::AuthError, "Graph rejected the token (401)" unless @ok

          true
        end
      end

      # A Store stand-in whose read raises, standing in for an Airtable outage.
      class ExplodingStore
        def budgets
          raise ::Reimbursements::Airtable::Error.new("Airtable unreachable", status: 500)
        end
      end

      setup do
        grant_finance_permission(users(:member))
        @user = users(:member)
        @cost_centre = ::Reimbursements::CostCentre.default

        @budget = airtable_budget_record(id: "recBud1", name: "Props", nominal_code: "4000")
        @store, @client = build_fake_store(budgets: [ @budget ])
        BaseController.store_builder = -> { @store }
        StatusController.graph_builder = -> { FakeGraph.new }
      end

      teardown do
        BaseController.store_builder = -> { ::Reimbursements::Store.new }
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

        with_env(GRAPH_ENV.merge(GEMINI_ENV)) { post :run }

        assert_response :success
        assert_includes response.body, "Airtable"
        assert_includes response.body, "read 1 budget(s)"
        assert_includes response.body, "Microsoft Graph"
        assert_includes response.body, "acquired an app token"
        assert_includes response.body, "Gemini"
        assert_includes response.body, "API key configured"
      end

      test "run flags Microsoft Graph with the error message when the token probe raises" do
        StatusController.graph_builder = -> { FakeGraph.new(ok: false) }
        sign_in @user

        with_env(GRAPH_ENV.merge(GEMINI_ENV)) { post :run }

        assert_response :success
        assert_includes response.body, "Graph rejected the token (401)"
        # A Graph failure must not hide the other (passing) checks.
        assert_includes response.body, "read 1 budget(s)"
      end

      test "run flags Airtable with the error message when the read raises" do
        BaseController.store_builder = -> { ExplodingStore.new }
        sign_in @user

        with_env(GRAPH_ENV.merge(GEMINI_ENV)) { post :run }

        assert_response :success
        assert_includes response.body, "Airtable unreachable"
        # The page degrades gracefully rather than 500ing.
        assert_includes response.body, "acquired an app token"
      end

      test "run skips Gemini when no API key is configured" do
        sign_in @user

        # Gemini env deliberately unset (test-env default), Graph configured.
        with_env(GRAPH_ENV) { post :run }

        assert_response :success
        assert_includes response.body, "AI checks are disabled"
      end

      test "run skips Graph when the Azure credentials are absent" do
        sign_in @user

        # Azure env deliberately unset (test-env default), Gemini configured.
        with_env(GEMINI_ENV) { post :run }

        assert_response :success
        assert_includes response.body, "No Azure credentials configured yet"
      end

      test "run still shows the last nightly-run date alongside the probe results" do
        @cost_centre.update!(last_nightly_run_on: Date.new(2026, 6, 30))
        sign_in @user

        with_env(GRAPH_ENV.merge(GEMINI_ENV)) { post :run }

        assert_response :success
        assert_includes response.body, "2026-06-30"
      end

      test "run answers a turbo stream that updates the results in place" do
        sign_in @user

        with_env(GRAPH_ENV.merge(GEMINI_ENV)) { post :run, as: :turbo_stream }

        assert_response :success
        assert_includes response.media_type, "turbo-stream"
        assert_includes response.body, "integration_check_results"
      end
    end
  end
end
