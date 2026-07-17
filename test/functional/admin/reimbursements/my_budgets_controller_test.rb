require "test_helper"

module Admin
  module Reimbursements
    class MyBudgetsControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      setup do
        producer = Role.create!(name: "Producer")
        producer.permissions << Permission.create(action: "access", subject_class: "reimbursements")
        users(:member).add_role("Producer")
        @user = users(:member)

        # The signed-in user's linked person (recPer1) owns recBud1, not recBud2.
        @owner = airtable_person_record(id: "recPer1", email: @user.email, name: "Olive Owner")
        @other = airtable_person_record(id: "recPerOther", email: "other@example.com", name: "Sam Submitter")
        @owned = airtable_budget_record(id: "recBud1", name: "Owned budget", owner_ids: [ "recPer1" ])
        @not_owned = airtable_budget_record(id: "recBud2", name: "Someone else's", owner_ids: [ "recPer9" ])
        # Pending claim by a non-owner on the owned budget -> awaits endorsement.
        @pending = airtable_expense_record(id: "recExp1", payee_id: "recPerOther", budget_id: "recBud1",
                                           status: "Pending", description: "Van hire")
        rebuild_store
      end

      teardown { BaseController.store_builder = -> { ::Reimbursements::Store.new } }

      def rebuild_store(expenses: nil)
        @store, @client = build_fake_store(
          people: [ @owner, @other ], budgets: [ @owned, @not_owned ],
          expenses: expenses || [ @pending ]
        )
        BaseController.store_builder = -> { @store }
      end

      test "requires sign-in" do
        get :index
        assert_redirected_to new_user_session_path
      end

      test "denies members without the reimbursements permission" do
        sign_in users(:committee)
        get :index
        assert_response :forbidden
      end

      test "lists only the budgets the signed-in owner owns, with pending claims" do
        sign_in @user
        get :index

        assert_response :success
        assert_includes response.body, "Owned budget"
        assert_not_includes response.body, "Someone else's"
        assert_includes response.body, "Van hire"
        assert_select "form[action=?]", admin_reimbursements_endorse_my_budget_path("recExp1")
      end

      test "shows an empty state for a person who owns no budgets" do
        @owned = airtable_budget_record(id: "recBud1", name: "Owned budget", owner_ids: [ "recPerNobody" ])
        rebuild_store
        sign_in @user
        get :index

        assert_response :success
        assert_includes response.body, "don't own any budgets"
      end

      test "a claim the owner submitted themselves shows as auto-cleared, not an Endorse button" do
        own = airtable_expense_record(id: "recExp2", payee_id: "recPer1", budget_id: "recBud1",
                                      status: "Pending", description: "My own claim")
        rebuild_store(expenses: [ own ])
        sign_in @user
        get :index

        assert_response :success
        assert_includes response.body, "Submitted by an owner"
        assert_select "form[action=?]", admin_reimbursements_endorse_my_budget_path("recExp2"), 0
      end

      test "a claim already endorsed (covering the amount) shows who endorsed it, no Endorse button" do
        ::Reimbursements::OwnerEndorsement.create!(expense_record_id: "recExp1", budget_record_id: "recBud1",
                                                   endorsed_by_person_id: "recPer1", endorsed_amount: BigDecimal("12.5"),
                                                   endorsed_at: Time.current)
        sign_in @user
        get :index

        assert_response :success
        assert_includes response.body, "Endorsed by Olive Owner"
        assert_select "form[action=?]", admin_reimbursements_endorse_my_budget_path("recExp1"), 0
      end

      test "a finance-overridden claim shows as cleared by finance" do
        ::Reimbursements::OwnerEndorsement.create!(expense_record_id: "recExp1", budget_record_id: "recBud1",
                                                   overridden_by: @user, endorsed_amount: BigDecimal("12.5"),
                                                   endorsed_at: Time.current)
        sign_in @user
        get :index

        assert_response :success
        assert_includes response.body, "Cleared by finance"
      end

      test "a stale endorsement (amount since edited) shows Endorse again, not Endorsed" do
        # Endorsed at £5, but the claim's actual amount is 12.5 — the sign-off no
        # longer covers it, so the owner is asked to endorse the current terms.
        ::Reimbursements::OwnerEndorsement.create!(expense_record_id: "recExp1", budget_record_id: "recBud1",
                                                   endorsed_by_person_id: "recPer1", endorsed_amount: BigDecimal("5"),
                                                   endorsed_at: Time.current)
        sign_in @user
        get :index

        assert_response :success
        assert_select "form[action=?]", admin_reimbursements_endorse_my_budget_path("recExp1")
        assert_not_includes response.body, "Endorsed by"
      end

      test "endorse records the current owner's endorsement" do
        sign_in @user

        assert_difference -> { ::Reimbursements::OwnerEndorsement.count }, 1 do
          post :endorse, params: { expense_id: "recExp1" }
        end

        assert_redirected_to admin_reimbursements_my_budgets_path
        endorsement = ::Reimbursements::OwnerEndorsement.for_expense("recExp1").first
        assert_equal "recPer1", endorsement.endorsed_by_person_id
        assert_equal "recBud1", endorsement.budget_record_id
        assert_equal BigDecimal("12.5"), endorsement.endorsed_amount, "snapshots the amount signed off"
        assert endorsement.owner_endorsement?
      end

      test "endorsing again is idempotent (any one owner suffices)" do
        sign_in @user
        ::Reimbursements::OwnerEndorsement.create!(expense_record_id: "recExp1", budget_record_id: "recBud1",
                                                   endorsed_by_person_id: "recPerElse", endorsed_at: Time.current)

        assert_no_difference -> { ::Reimbursements::OwnerEndorsement.count } do
          post :endorse, params: { expense_id: "recExp1" }
        end
        assert_redirected_to admin_reimbursements_my_budgets_path
      end

      test "refuses to endorse a claim on a budget the person does not own" do
        # recExp3 is charged to recBud2, owned by recPer9 — not the signed-in user.
        other_budget_expense = airtable_expense_record(id: "recExp3", payee_id: "recPerOther",
                                                       budget_id: "recBud2", status: "Pending")
        rebuild_store(expenses: [ @pending, other_budget_expense ])
        sign_in @user

        assert_no_difference -> { ::Reimbursements::OwnerEndorsement.count } do
          post :endorse, params: { expense_id: "recExp3" }
        end
        assert_redirected_to admin_reimbursements_my_budgets_path
        assert_match(/only endorse expenses on budgets you own/i, flash[:alert])
      end
    end
  end
end
