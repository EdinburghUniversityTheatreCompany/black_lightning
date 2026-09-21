require "test_helper"

module Admin
  module Reimbursements
    ##
    # The portal's front door. Two audiences share one URL: a finance user gets
    # the dashboard, a producer is redirected to their own claims — which is
    # what this URL did for EVERYBODY before, and the whole reason the business
    # manager was greeted with "Submit your expenses here".
    class HomeControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      setup do
        @user = users(:member)
        grant_finance_permission(@user)
        @cost_centre = ::Reimbursements::CostCentre.default
        @person = create_reimbursements_person(name: "Pat Producer", email: "pat@example.com")
      end

      # --- Who lands where ---------------------------------------------------

      test "requires sign-in" do
        get :show
        assert_redirected_to new_user_session_path
      end

      test "a finance user gets the dashboard" do
        sign_in @user
        get :show
        assert_response :success
        assert_equal "Finance home", assigns(:title)
      end

      test "a producer is sent to their own claims rather than refused" do
        other = users(:member_with_phone_number)
        grant_producer_permission(other)
        sign_in other
        get :show
        assert_redirected_to admin_reimbursements_expenses_path
      end

      # --- The figures -------------------------------------------------------

      test "splits the claims queue the way the Review tabs do" do
        budget = create_reimbursements_budget(name: "Props", cost_centre: @cost_centre)
        owned = create_reimbursements_budget(name: "Set", cost_centre: @cost_centre,
                                             owners: [ create_reimbursements_person(name: "Olive Owner",
                                                                                    email: "olive@example.com") ])
        create_reimbursements_expense(person: @person, budget: budget, amount: BigDecimal("30"))
        create_reimbursements_expense(person: @person, budget: owned, amount: BigDecimal("40"))
        create_reimbursements_expense(person: @person, budget: budget, amount: BigDecimal("50"),
                                      status: ::Reimbursements::Status::APPROVED)

        sign_in @user
        get :show
        home = assigns(:home)

        assert_equal 1, home.to_approve.size
        assert_equal BigDecimal("30"), home.to_approve_total
        assert_equal 1, home.awaiting_owner.size
        assert_equal BigDecimal("40"), home.awaiting_owner_total
        assert_equal 1, home.approved.size
        assert_equal BigDecimal("50"), home.approved_total
      end

      test "totals are the GROSS amount, which is what EUSA pays" do
        budget = create_reimbursements_budget(name: "Props", cost_centre: @cost_centre)
        create_reimbursements_expense(person: @person, budget: budget,
                                      amount: BigDecimal("120"), amount_excl_vat: BigDecimal("100"),
                                      status: ::Reimbursements::Status::APPROVED)

        sign_in @user
        get :show

        assert_equal BigDecimal("120"), assigns(:home).approved_total
      end

      test "names the most recent batch by BACS date" do
        older = create_reimbursements_batch(date_sent: Date.new(2026, 5, 1), name: "Older")
        newer = create_reimbursements_batch(date_sent: Date.new(2026, 6, 1), name: "Newer")
        budget = create_reimbursements_budget(name: "Props", cost_centre: @cost_centre)
        create_reimbursements_expense(person: @person, budget: budget, batch: newer,
                                      amount: BigDecimal("75"),
                                      status: ::Reimbursements::Status::SUBMITTED)

        sign_in @user
        get :show
        home = assigns(:home)

        assert_equal newer.record_id, home.last_batch.record_id
        refute_equal older.record_id, home.last_batch.record_id
        assert_equal 1, home.last_batch_expenses.size
        assert_equal BigDecimal("75"), home.last_batch_total
      end

      test "counts the ledger rows no budget accounts for" do
        create_reimbursements_actual(nominal_code: "439999", narrative: "Unlinked",
                                     debit: BigDecimal("60"))

        sign_in @user
        get :show
        home = assigns(:home)

        assert_equal 1, home.unattributed_count
        assert_equal BigDecimal("60"), home.unattributed_total
      end

      test "counts over-budget lines, worst first, and agrees with the Overview" do
        year = ::Reimbursements::FinancialYear.current
        under = create_reimbursements_budget(name: "Under", cost_centre: @cost_centre,
                                             financial_year: year, initial_budget: BigDecimal("500"))
        slightly = create_reimbursements_budget(name: "Slightly", cost_centre: @cost_centre,
                                                financial_year: year, initial_budget: BigDecimal("100"))
        badly = create_reimbursements_budget(name: "Badly", cost_centre: @cost_centre,
                                             financial_year: year, initial_budget: BigDecimal("100"))
        create_reimbursements_expense(person: @person, budget: under, amount: BigDecimal("10"),
                                      amount_excl_vat: BigDecimal("10"),
                                      status: ::Reimbursements::Status::PAID)
        create_reimbursements_expense(person: @person, budget: slightly, amount: BigDecimal("150"),
                                      amount_excl_vat: BigDecimal("150"),
                                      status: ::Reimbursements::Status::PAID)
        create_reimbursements_expense(person: @person, budget: badly, amount: BigDecimal("900"),
                                      amount_excl_vat: BigDecimal("900"),
                                      status: ::Reimbursements::Status::PAID)

        sign_in @user
        get :show
        home = assigns(:home)

        assert_equal 2, home.over_budget_count
        assert_equal [ "Badly", "Slightly" ], home.over_budget_lines.map(&:name)
      end

      test "a line with no budget set is not counted as over budget" do
        year = ::Reimbursements::FinancialYear.current
        unset = create_reimbursements_budget(name: "Unset", cost_centre: @cost_centre,
                                             financial_year: year, initial_budget: nil)
        zero = create_reimbursements_budget(name: "Zero", cost_centre: @cost_centre,
                                            financial_year: year, initial_budget: BigDecimal("0"))
        [ unset, zero ].each do |budget|
          create_reimbursements_expense(person: @person, budget: budget, amount: BigDecimal("40"),
                                        amount_excl_vat: BigDecimal("40"),
                                        status: ::Reimbursements::Status::PAID)
        end

        sign_in @user
        get :show

        assert_equal 0, assigns(:home).over_budget_count
      end

      # --- Scoping -----------------------------------------------------------

      test "?cost_centre= scopes the figures to that pot" do
        other = seed_two_cost_centres

        sign_in @user
        get :show, params: { cost_centre: other.key }

        assert_equal BigDecimal("22"), assigns(:home).to_approve_total
        assert_equal [ other ], assigns(:home).reminder_cost_centres
      end

      test "no cost centre means every centre, for the figures and the reminders" do
        seed_two_cost_centres

        sign_in @user
        get :show

        assert_equal BigDecimal("33"), assigns(:home).to_approve_total
        assert_equal 2, assigns(:home).reminder_cost_centres.size
      end

      # --- What the page says ------------------------------------------------

      test "links the weekly loop's next screens" do
        sign_in @user
        get :show

        assert_select "a[href=?]", admin_reimbursements_review_path(tab: "to_approve")
        assert_select "a[href=?]", new_admin_reimbursements_batch_path
        assert_select "a[href=?]", admin_reimbursements_actuals_path
        assert_select "a[href=?]", admin_reimbursements_reconciliation_path
      end

      test "renders with an empty portal" do
        ::Reimbursements::Expense.delete_all
        ::Reimbursements::Budget.delete_all

        sign_in @user
        get :show

        assert_response :success
        assert_select "body", /No batch has been built yet/
      end

      private

      # A claim of £11 in the fixture centre and one of £22 in a second one,
      # so a scoped read and an unscoped one report different totals. Shared
      # rather than repeated: jscpd gates duplication at 0.
      def seed_two_cost_centres
        other = create_second_reimbursements_cost_centre
        mine = create_reimbursements_budget(name: "Mine", cost_centre: @cost_centre)
        theirs = create_reimbursements_budget(name: "Theirs", cost_centre: other)
        create_reimbursements_expense(person: @person, budget: mine, amount: BigDecimal("11"))
        create_reimbursements_expense(person: @person, budget: theirs, amount: BigDecimal("22"))
        other
      end
    end
  end
end
