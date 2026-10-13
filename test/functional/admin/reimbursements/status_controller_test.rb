require "test_helper"

module Admin
  module Reimbursements
    class StatusControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      setup do
        grant_finance_permission(users(:member))
        @user = users(:member)
        @cost_centre = ::Reimbursements::CostCentre.default
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

      test "flags a cost centre with no notification address" do
        # update_columns, not update!: reproduces a blank address that predates the validation.
        ::Reimbursements::CostCentre.default.update_columns(notification_email: nil)
        sign_in @user

        get :show

        assert_response :success
        assert_includes response.body, "No notification recipients"
      end

      test "counts several addresses" do
        @cost_centre.update!(notification_email: "finance@b.co; business@b.co")
        sign_in @user

        get :show

        assert_response :success
        assert_includes response.body, "2 addresses"
        assert_includes response.body, "finance@b.co"
        assert_not_includes response.body, "No notification recipients"
      end

      test "links each cost centre's recipients to that centre's own settings page" do
        sign_in @user

        get :show

        assert_response :success
        assert_includes response.body,
                        edit_admin_reimbursements_setting_path(@cost_centre.key)
      end

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

      # An unlogged email that went out beats a logged one that did not.
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
