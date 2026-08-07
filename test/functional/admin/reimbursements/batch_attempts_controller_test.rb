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

      test "dismissing clears the alert" do
        attempt = build_attempt(status: "failed", error_messages: "Graph rejected the token (403)")

        post :dismiss, params: { id: attempt.id }

        assert_redirected_to admin_reimbursements_batches_path
        assert_predicate attempt.reload, :dismissed?
        assert_not_includes ::Reimbursements::BatchAttempt.needing_attention, attempt
      end

      test "records who dismissed it" do
        attempt = build_attempt(status: "failed", error_messages: "boom")

        post :dismiss, params: { id: attempt.id }

        assert_equal @user.email, attempt.reload.dismissed_by_email
      end

      test "the failure itself is left on the record" do
        attempt = build_attempt(status: "failed", error_messages: "boom", batch_record_id: "recBat9")

        post :dismiss, params: { id: attempt.id }
        attempt.reload

        assert_predicate attempt, :failed?
        assert_equal "boom", attempt.error_messages
        assert_equal "recBat9", attempt.batch_record_id
      end

      test "refuses to dismiss a build that is still running" do
        # Hiding a live build would leave the operator thinking nothing is in
        # flight, and a rebuild on top of it is exactly what the alert prevents.
        attempt = build_attempt

        post :dismiss, params: { id: attempt.id }

        assert_not attempt.reload.dismissed?
        assert_match(/still running/i, flash[:alert])
      end

      test "a stale build can be dismissed" do
        attempt = build_attempt

        travel_to (::Reimbursements::BatchAttempt::STALE_AFTER + 1.minute).from_now do
          post :dismiss, params: { id: attempt.id }
        end

        assert_predicate attempt.reload, :dismissed?
      end

      test "a producer without the finance permission cannot dismiss" do
        attempt = build_attempt(status: "failed", error_messages: "boom")
        producer = FactoryBot.create(:user)
        grant_producer_permission(producer)
        sign_in producer

        post :dismiss, params: { id: attempt.id }

        assert_response :forbidden
        assert_not attempt.reload.dismissed?
      end

      test "404s on an unknown attempt" do
        # ApplicationController rescues RecordNotFound into its 404 page rather
        # than letting it raise.
        post :dismiss, params: { id: 0 }

        assert_response :not_found
      end
    end
  end
end
