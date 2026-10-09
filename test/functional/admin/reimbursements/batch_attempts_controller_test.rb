require "test_helper"

module Admin
  module Reimbursements
    class BatchAttemptsControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      tests Admin::Reimbursements::BatchAttemptsController

      setup do
        @user = users(:member)
        grant_finance_permission(@user)
        sign_in @user
      end

      def build_attempt(**attrs)
        ::Reimbursements::BatchAttempt.create!(
          cost_centre: ::Reimbursements::CostCentre.default,
          bacs_date: Date.new(2026, 8, 7), **attrs
        )
      end

      test "dismissing clears the alert and records who did it" do
        attempt = build_attempt(status: "failed", error_messages: "Graph rejected the token (403)")

        post :dismiss, params: { id: attempt.id }

        assert_redirected_to admin_reimbursements_batches_path
        assert_not_nil attempt.reload.dismissed_at
        assert_not_includes ::Reimbursements::BatchAttempt.needing_attention, attempt
        assert_equal @user.email, attempt.dismissed_by_email
      end

      test "dismissing comes back to the centre History was showing" do
        termtime = create_second_reimbursements_cost_centre
        attempt = build_attempt(status: "failed", error_messages: "boom")

        post :dismiss, params: { id: attempt.id, cost_centre: termtime.key }

        assert_redirected_to admin_reimbursements_batches_path(cost_centre: termtime.key)
      end

      test "refuses to dismiss a build that is still running" do
        # Hiding a live build invites a rebuild on top of it.
        attempt = build_attempt

        post :dismiss, params: { id: attempt.id }

        assert_nil attempt.reload.dismissed_at
        assert_match(/still running/i, flash[:alert])
      end

      test "a stale build can be dismissed" do
        attempt = build_attempt

        travel_to (::Reimbursements::BatchAttempt::STALE_AFTER + 1.minute).from_now do
          post :dismiss, params: { id: attempt.id }
        end

        assert_not_nil attempt.reload.dismissed_at
      end

      test "a producer without the finance permission cannot dismiss" do
        attempt = build_attempt(status: "failed", error_messages: "boom")
        producer = FactoryBot.create(:user)
        grant_producer_permission(producer)
        sign_in producer

        post :dismiss, params: { id: attempt.id }

        assert_response :forbidden
        assert_nil attempt.reload.dismissed_at
      end

      test "404s on an unknown attempt" do
        # ApplicationController rescues RecordNotFound into its 404 page.
        post :dismiss, params: { id: 0 }

        assert_response :not_found
      end
    end
  end
end
