require "test_helper"

module Reimbursements
  class ExpensesControllerTest < ActionController::TestCase
    include ReimbursementsTestHelpers

    setup do
      @user = users(:user)
      @store, @client = build_fake_store(
        expenses: [ airtable_expense_record, airtable_expense_record(id: "recExp2", payee_id: "recPerOther", description: "Someone else's") ],
        people: [ airtable_person_record(email: @user.email), airtable_person_record(id: "recPerOther", email: "other@example.com") ],
        budgets: [ airtable_budget_record ]
      )
      BaseController.store_builder = -> { @store }
    end

    teardown do
      BaseController.store_builder = -> { Store.new }
      BaseController.extractor_builder = -> { Extractor.new }
    end

    test "requires sign-in" do
      get :index
      assert_redirected_to new_user_session_path
    end

    test "shows only the current user's expenses" do
      sign_in @user

      get :index

      assert_response :success
      assert_equal [ "recExp1" ], assigns(:expenses).map(&:record_id)
      assert_includes response.body, "Fake blood"
      assert_not_includes response.body, "Someone else&#39;s"
    end

    test "links the user to their airtable person by email on first visit" do
      sign_in @user
      assert_nil @user.airtable_person_id

      get :index

      assert_equal "recPer1", @user.reload.airtable_person_id
    end

    test "refresh busts the cache and redirects to a clean url" do
      sign_in @user

      get :index
      assert_equal 1, @client.list_calls[:expenses]

      get :index, params: { refresh: 1 }
      assert_redirected_to reimbursements_expenses_path

      get :index
      assert_equal 2, @client.list_calls[:expenses]
    end

    test "prompts for payment details when bank details are missing" do
      sign_in @user

      get :index

      assert_includes response.body, "add your payment details"
    end

    test "shows an empty state for users with no expenses" do
      other = users(:member)
      sign_in other

      get :index

      assert_response :success
      assert_includes response.body, "No expenses yet"
    end
  end
end
