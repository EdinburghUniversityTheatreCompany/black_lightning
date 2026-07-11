require "test_helper"

module Admin
  module Reimbursements
  class ActualsControllerTest < ActionController::TestCase
    include ReimbursementsTestHelpers

    setup do
      finance = Role.create!(name: "Business Manager")
      finance.permissions << Permission.create(action: "manage", subject_class: "reimbursements_finance")
      users(:member).add_role("Business Manager")
      @user = users(:member)

      @linked_expense = airtable_eusa_actual_record(
        id: "recActExp", nominal_code: "439999", period: "03", narrative: "Alice Producer",
        date: "2026-05-13", debit: 123.45, linked_expense: [ "recExp1" ],
        imported_at: "2026-05-20T10:00:00Z"
      )
      @linked_budget = airtable_eusa_actual_record(
        id: "recActBud", nominal_code: "250000", period: "03", narrative: "Box office",
        date: "2026-05-14", debit: nil, credit: 500.0, linked_budget: [ "recBud1" ],
        imported_at: "2026-05-20T11:00:00Z"
      )
      @unlinked = airtable_eusa_actual_record(
        id: "recActNone", nominal_code: "500000", period: "04", narrative: "Sundry",
        date: "2026-06-01", debit: 42.0, imported_at: "2026-06-05T09:00:00Z"
      )

      rebuild_store(eusa_actuals: [ @linked_expense, @linked_budget, @unlinked ])
    end

    teardown do
      BaseController.store_builder = -> { ::Reimbursements::Store.new }
    end

    def rebuild_store(eusa_actuals: [])
      @store, @client = build_fake_store(eusa_actuals: eusa_actuals)
      BaseController.store_builder = -> { @store }
    end

    # --- Auth gating -------------------------------------------------------

    test "requires sign-in" do
      get :index
      assert_redirected_to new_user_session_path
    end

    test "denies members without the finance permission" do
      sign_in users(:committee)
      get :index
      assert_response :forbidden
    end

    test "the producer portal permission alone does not grant finance access" do
      producer_role = Role.create!(name: "Producer")
      producer_role.permissions << Permission.create(action: "access", subject_class: "reimbursements")
      submitter = users(:member_with_phone_number)
      submitter.add_role("Producer")
      sign_in submitter

      # The period-filtered route is gated the same as the bare index.
      get :index, params: { period: "03" }

      assert_response :forbidden
    end

    # --- Index -------------------------------------------------------------

    test "lists every imported actual, newest imported first" do
      sign_in @user
      get :index

      assert_response :success
      assert_equal %w[recActNone recActBud recActExp], assigns(:actuals).map(&:record_id)
      assert_includes response.body, "Alice Producer"
      assert_includes response.body, "Box office"
      assert_includes response.body, "Sundry"
    end

    test "shows the linked-to state per row" do
      sign_in @user
      get :index

      assert_response :success
      assert_includes response.body, "Expense"
      assert_includes response.body, "Budget"
      assert_includes response.body, "Unlinked"
    end

    test "filters by period" do
      sign_in @user
      get :index, params: { period: "04" }

      assert_response :success
      assert_equal %w[recActNone], assigns(:actuals).map(&:record_id)
    end

    test "offers the distinct periods as filter options" do
      sign_in @user
      get :index

      assert_response :success
      assert_equal %w[03 04], assigns(:periods)
    end

    test "renders an empty state when nothing has been imported" do
      rebuild_store(eusa_actuals: [])
      sign_in @user
      get :index

      assert_response :success
      assert_empty assigns(:actuals)
      assert_includes response.body, "No EUSA Actuals imported yet."
    end
  end
  end
end
