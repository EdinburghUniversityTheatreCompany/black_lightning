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

      test "shares that cannot be written are refused and write nothing" do
        # "not offered": posted ids are checked against the ids the page RENDERED.
        hidden = create_reimbursements_budget(name: "Retired", budget_type: "Income", active: false)
        sign_in @user

        { "short" => { "0" => { budget_id: @show_a.record_id, amount: "3880" } },
          "not offered" => { "0" => { budget_id: hidden.record_id, amount: "4000" } },
          "unreadable" => { "0" => { budget_id: @show_a.record_id, amount: "four thousand" } },
          "duplicate" => { "0" => { budget_id: @show_a.record_id, amount: "2000" },
                           "1" => { budget_id: @show_a.record_id, amount: "2000" } } }.each do |label, shares|
          post_split(shares)

          assert_response :unprocessable_entity, label
          assert_empty @payout.reload.allocations, label
        end
      end

      test "a blank row is dropped rather than refused" do
        sign_in @user

        post_split(two_way_split.merge("2" => { budget_id: "", amount: "" }))

        assert_redirected_to admin_reimbursements_actuals_path
        assert_equal 2, @payout.reload.allocations.count
      end

      test "removing the split restores the row to unlinked" do
        sign_in @user
        post_split(two_way_split)

        post :remove_apportionment, params: { id: @payout.record_id }

        assert_redirected_to admin_reimbursements_actuals_path
        assert_empty @payout.reload.allocations
        assert_predicate @payout, :apportionable?
      end

      # state=all: a split row is finished with, so the default view leaves it out.
      test "the ledger row names its shares and offers the undo" do
        sign_in @user
        post_split(two_way_split)

        get :index, params: { state: "all" }

        assert_response :success
        assert_match "Show A £2,500.00; Show B £1,500.00", response.body
        assert_match "Remove split", response.body
      end

      test "an apportionable row offers the split action on the index" do
        sign_in @user

        get :index

        assert_match "Split across budgets", response.body
      end
    end
  end
end
