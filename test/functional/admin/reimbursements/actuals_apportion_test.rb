require "test_helper"

module Admin
  module Reimbursements
    ##
    # Splitting one EUSA credit row across several income budgets: the screen,
    # its refusals, and the undo.
    class ActualsApportionTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      tests ActualsController

      setup do
        grant_finance_permission(users(:member))
        @user = users(:member)
        @payout = create_reimbursements_eusa_actual(credit: BigDecimal("4000"),
                                                    narrative: "STRIPE PAYOUT AUG")
        @show_a = create_reimbursements_budget(name: "Show A", budget_type: "Income",
                                               nominal_code: "4100")
        @show_b = create_reimbursements_budget(name: "Show B", budget_type: "Income",
                                               nominal_code: "4100")
      end

      def post_split(shares, id: @payout.record_id)
        post :create_apportionment, params: { id: id, shares: shares }
      end

      def two_way_split
        { "0" => { budget_id: @show_a.record_id, amount: "2500" },
          "1" => { budget_id: @show_b.record_id, amount: "1,500" } }
      end

      test "the form renders for an apportionable credit row" do
        sign_in @user

        get :apportion, params: { id: @payout.record_id }

        assert_response :success
        assert_match "Show A", response.body
      end

      test "a debit row cannot reach the form" do
        sign_in @user
        debit = create_reimbursements_eusa_actual(debit: BigDecimal("50"))

        get :apportion, params: { id: debit.record_id }

        assert_redirected_to admin_reimbursements_actuals_path
        assert flash[:alert].present?
      end

      test "shares that sum to the row are written and the row is stamped" do
        sign_in @user

        post_split(two_way_split)

        assert_redirected_to admin_reimbursements_actuals_path
        assert_equal [ BigDecimal("1500"), BigDecimal("2500") ],
                     @payout.reload.allocations.map(&:amount).sort
        assert_nil @payout[:budget_id]
      end

      test "shares that do not sum to the row are refused and write nothing" do
        sign_in @user

        post_split({ "0" => { budget_id: @show_a.record_id, amount: "3880" } })

        assert_response :unprocessable_entity
        assert_empty @payout.reload.allocations
      end

      # The picker is drawn from a scoped list while the write is unscoped —
      # the shape of the area-select bug. The posted ids are checked against
      # the ids this page actually RENDERED.
      test "a budget the form did not offer is refused" do
        sign_in @user
        hidden = create_reimbursements_budget(name: "Retired", budget_type: "Income",
                                              active: false)

        post_split({ "0" => { budget_id: hidden.record_id, amount: "4000" } })

        assert_response :unprocessable_entity
        assert_empty @payout.reload.allocations
      end

      test "an unreadable amount is refused rather than stored as zero" do
        sign_in @user

        post_split({ "0" => { budget_id: @show_a.record_id, amount: "four thousand" } })

        assert_response :unprocessable_entity
        assert_empty @payout.reload.allocations
      end

      test "a blank row is dropped rather than refused" do
        sign_in @user

        post_split(two_way_split.merge("2" => { budget_id: "", amount: "" }))

        assert_redirected_to admin_reimbursements_actuals_path
        assert_equal 2, @payout.reload.allocations.count
      end

      test "the same budget twice is refused" do
        sign_in @user

        post_split({ "0" => { budget_id: @show_a.record_id, amount: "2000" },
                     "1" => { budget_id: @show_a.record_id, amount: "2000" } })

        assert_response :unprocessable_entity
        assert_empty @payout.reload.allocations
      end

      test "removing the split restores the row to unlinked" do
        sign_in @user
        post_split(two_way_split)

        post :remove_apportionment, params: { id: @payout.record_id }

        assert_redirected_to admin_reimbursements_actuals_path
        assert_empty @payout.reload.allocations
        assert_predicate @payout, :apportionable?
      end

      # Splitting a row moves money between budgets' figures, so it is behind
      # the same finance gate as the rest of this controller rather than the
      # producer portal's.
      test "portal access alone does not open the split screen" do
        grant_producer_permission(users(:member_with_phone_number))
        sign_in users(:member_with_phone_number)

        get :apportion, params: { id: @payout.record_id }

        assert_response :forbidden
      end

      test "portal access alone cannot remove a split" do
        grant_producer_permission(users(:member_with_phone_number))
        sign_in users(:member_with_phone_number)

        post :remove_apportionment, params: { id: @payout.record_id }

        assert_response :forbidden
      end
    end
  end
end
