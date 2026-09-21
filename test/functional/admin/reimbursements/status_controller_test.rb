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

      test "flags a cost centre with no notification address" do
        # update_columns, not update!: presence is validated on the model, so
        # this is the only way to reproduce a row that predates the validation.
        ::Reimbursements::CostCentre.default.update_columns(notification_email: nil)
        sign_in @user

        get :show

        assert_response :success
        assert_includes response.body, "No notification recipients"
      end

      test "does not flag a cost centre that has one" do
        @cost_centre.update!(notification_email: "finance@bedlamfringe.co.uk")
        sign_in @user

        get :show

        assert_response :success
        assert_not_includes response.body, "No notification recipients"
        assert_includes response.body, "finance@bedlamfringe.co.uk"
      end

      test "counts several addresses" do
        @cost_centre.update!(notification_email: "finance@b.co; business@b.co")
        sign_in @user

        get :show

        assert_response :success
        assert_includes response.body, "2 addresses"
      end

      test "names the third nightly reminder, the one budget owners get" do
        sign_in @user

        get :show

        assert_response :success
        assert_includes response.body, "budget owner"
        assert_includes response.body, "sign-off"
      end

      test "links each cost centre's recipients to that centre's own settings page" do
        sign_in @user

        get :show

        assert_response :success
        assert_includes response.body,
                        edit_admin_reimbursements_setting_path(@cost_centre.key)
      end

      # A code comment about #run_checks was typed into the card's visible copy
      # and rendered to finance users. It belongs beside the method.
      test "does not render the run_checks implementation note on screen" do
        sign_in @user

        get :show

        assert_response :success
        assert_not_includes response.body, "#run_checks"
        assert_not_includes response.body, "one-line change"
      end

      test "run answers a turbo stream that updates the results in place" do
        sign_in @user

        with_env(GRAPH_ENV) { post :run, as: :turbo_stream }

        assert_response :success
        assert_includes response.media_type, "turbo-stream"
        assert_includes response.body, "integration_check_results"
      end

      # --- The send log ------------------------------------------------------
      # The page could say whether Graph was reachable and when each centre's
      # nightly last completed, and nothing about what was sent to whom — so
      # "did this person get their reminder?" had no answer short of asking.

      def logged_send(recipient:, kind: "pending_reminder", sent_at: Time.current,
                      subject: "Claims waiting", cost_centre: nil)
        ::Reimbursements::NotificationLog.create!(
          kind: kind, recipient: recipient, subject: subject, sent_at: sent_at,
          cost_centre: cost_centre || @cost_centre
        )
      end

      test "the page lists what has been emailed, newest first" do
        logged_send(recipient: "older@example.com", sent_at: 2.days.ago)
        logged_send(recipient: "newer@example.com", sent_at: 1.hour.ago)
        sign_in @user

        get :show

        assert_response :success
        assert_equal [ "newer@example.com", "older@example.com" ],
                     assigns(:sends).map(&:recipient)
      end

      test "searching by recipient answers did this person get it" do
        logged_send(recipient: "olive@example.com")
        logged_send(recipient: "someone.else@example.com")
        sign_in @user

        get :show, params: { recipient: "olive@example.com" }

        assert_equal [ "olive@example.com" ], assigns(:sends).map(&:recipient)
      end

      # A reminder to an address nobody reads looks exactly like this, so the
      # empty state says where to check rather than just "none".
      test "a recipient with nothing sent to them says so, and where to look" do
        sign_in @user

        get :show, params: { recipient: "nobody@example.com" }

        assert_empty assigns(:sends)
        assert_match(/Check the address on/, response.body)
      end

      test "counts per run day and kind" do
        2.times { |i| logged_send(recipient: "a#{i}@example.com", sent_at: Time.current) }
        logged_send(recipient: "b@example.com", kind: "owner_sign_off_reminder")
        sign_in @user

        get :show

        counts = assigns(:send_counts).to_h
        assert_equal 2, counts[[ Date.current, "pending_reminder" ]]
        assert_equal 1, counts[[ Date.current, "owner_sign_off_reminder" ]]
      end

      test "the log is scoped to the selected cost centre" do
        other = create_second_reimbursements_cost_centre
        logged_send(recipient: "ours@example.com", cost_centre: @cost_centre)
        logged_send(recipient: "theirs@example.com", cost_centre: other)
        sign_in @user

        get :show, params: { cost_centre: other.key }

        assert_equal [ "theirs@example.com" ], assigns(:sends).map(&:recipient)
      end

      # --- What the Notifier records ----------------------------------------

      test "sending an email records one row per recipient" do
        notifier = ::Reimbursements::Notifier.new(cost_centre: @cost_centre,
                                                  graph: FakeGraphClient.new)

        assert_difference -> { ::Reimbursements::NotificationLog.count }, 2 do
          notifier.pending_reminder(recipients: [ "one@example.com", "two@example.com" ],
                                    rows: [], run_date: Date.current, threshold_days: 3)
        end

        assert_equal %w[one@example.com two@example.com],
                     ::Reimbursements::NotificationLog.order(:recipient).pluck(:recipient)
        assert_equal "pending_reminder", ::Reimbursements::NotificationLog.first.kind
      end

      # An unlogged email that went out beats a logged one that did not, so the
      # recorder swallows its own failures rather than letting them reach the
      # caller — which for the Notifier is the send it has just made.
      test "a log write that cannot succeed raises nothing" do
        assert_nothing_raised do
          # sent_at is presence-validated, so create! raises inside .record.
          ::Reimbursements::NotificationLog.record(
            kind: "pending_reminder", recipients: [ "one@example.com" ],
            subject: "Claims waiting", cost_centre: @cost_centre, sent_at: nil
          )
        end

        assert_equal 0, ::Reimbursements::NotificationLog.count
      end

      test "a blank or repeated recipient is not logged twice" do
        ::Reimbursements::NotificationLog.record(
          kind: "pending_reminder", recipients: [ "one@example.com", " one@example.com ", "" ],
          subject: "Claims waiting", cost_centre: @cost_centre
        )

        assert_equal [ "one@example.com" ], ::Reimbursements::NotificationLog.pluck(:recipient)
      end
    end
  end
end
