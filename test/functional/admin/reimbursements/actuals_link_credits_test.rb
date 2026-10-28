require "test_helper"

module Admin
  module Reimbursements
    ##
    # "Link credits": unplaced credits whose nominal code exactly one income budget carries, put
    # on that budget in one go. Reconcile applies the same rule only at import, so a budget made
    # afterwards (termtime's membership, 15 rows on 359000) never picked up the rows before it.
    class ActualsLinkCreditsTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      tests ActualsController

      setup do
        grant_finance_permission(users(:member))
        sign_in users(:member)
        @membership = create_reimbursements_budget(name: "Membership", budget_type: "Income",
                                                   nominal_code: "359000")
        @fee = create_reimbursements_eusa_actual(nominal_code: "359000", credit: BigDecimal("640"),
                                                 narrative: "SUMS - EUTC BEDLAM THEATRE - STUDENT MEM")
      end

      test "the ledger offers to link a credit one income budget claims, and links it" do
        get :index

        assert_response :success
        assert_select "button", text: "Link 1 credit to its income budget"
        assert_select "li", text: /Membership: 1 credit, £640\.00/

        post :link_credits

        assert_redirected_to admin_reimbursements_actuals_path
        assert_equal @membership.id, @fee.reload.budget_id
        assert_equal "Linked 1 credit to its income budget.", flash[:notice]
      end

      test "a credit two income budgets share is left for a person" do
        create_reimbursements_budget(name: "Set hire", budget_type: "Income", nominal_code: "359000")

        get :index

        assert_select "button", text: /Link \d+ credit/, count: 0

        post :link_credits

        assert_nil @fee.reload.budget_id
      end

      # Production's "P5 F40 accrued ticket income": an estimate and its reversal, both unplaced.
      # Linking the credit alone would count £12,381.81 of income that never arrived.
      test "a credit with an unplaced row of the opposite amount is held back as a possible accrual" do
        create_reimbursements_eusa_actual(nominal_code: "359000", debit: BigDecimal("640"),
                                          narrative: "P5 accrual reversal")

        get :index

        assert_select "button", text: /Link \d+ credit/, count: 0
        assert_includes response.body, "1 credit held back"

        post :link_credits

        assert_nil @fee.reload.budget_id
        assert_match "1 credit held back", flash[:notice]
      end

      test "only the cost centre on screen is linked" do
        termtime = create_second_reimbursements_cost_centre
        @membership.update!(cost_centre: termtime)
        @fee.update!(cost_centre_id: termtime.id)
        fringe = ::Reimbursements::CostCentre.where.not(id: termtime.id).first

        post :link_credits, params: { cost_centre: fringe.key }

        assert_nil @fee.reload.budget_id

        post :link_credits, params: { cost_centre: termtime.key }

        assert_redirected_to admin_reimbursements_actuals_path(cost_centre: termtime.key)
        assert_equal @membership.id, @fee.reload.budget_id
      end

      # The plan is read before the click, so the write re-checks the row under a lock.
      test "a credit placed since the page was read is left where it is" do
        other = create_reimbursements_budget(name: "Hires", budget_type: "Income", nominal_code: "331300")
        @fee.update!(budget: other)

        assert_not ::Reimbursements.build_store.link_credit_to_budget!(@fee.id, @membership.id)
        assert_equal other.id, @fee.reload.budget_id
      end
    end
  end
end
