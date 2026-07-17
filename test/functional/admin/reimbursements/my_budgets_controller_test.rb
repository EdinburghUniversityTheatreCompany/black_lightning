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

        # The signed-in user's linked person owns @owned, not @not_owned.
        @owner = create_reimbursements_person(email: @user.email, name: "Olive Owner")
        @other = create_reimbursements_person(email: "other@example.com", name: "Sam Submitter")
        @stranger = create_reimbursements_person(email: "stranger@example.com", name: "Someone Else")
        @owned = create_reimbursements_budget(name: "Owned budget", owners: [ @owner ])
        @not_owned = create_reimbursements_budget(name: "Someone else's", owners: [ @stranger ])
        # Pending claim by a non-owner on the owned budget -> awaits endorsement.
        @pending = create_reimbursements_expense(person: @other, budget: @owned,
                                                 status: ::Reimbursements::Status::PENDING,
                                                 description: "Van hire")
        # Reject emails go through the Graph notifier; inject a recording fake.
        @graph = FakeGraphClient.new
        MyBudgetsController.notifier_builder =
          ->(mailbox:) { ::Reimbursements::Notifier.new(mailbox: mailbox, graph: @graph) }
      end

      teardown do
        MyBudgetsController.notifier_builder =
          ->(mailbox:) { ::Reimbursements::Notifier.new(mailbox: mailbox) }
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
        assert_not_includes response.body, "Someone else&#39;s"
        assert_includes response.body, "Van hire"
        assert_select "form[action=?]", admin_reimbursements_endorse_my_budget_path(@pending.record_id)
      end

      test "shows an empty state for a person who owns no budgets" do
        @owned.budget_ownerships.destroy_all
        @owned.owners << @stranger
        sign_in @user
        get :index

        assert_response :success
        assert_includes response.body, "don't own any budgets"
      end

      test "a claim the owner submitted themselves shows as auto-cleared, not an Endorse button" do
        @pending.destroy!
        own = create_reimbursements_expense(person: @owner, budget: @owned,
                                            status: ::Reimbursements::Status::PENDING,
                                            description: "My own claim")
        sign_in @user
        get :index

        assert_response :success
        assert_includes response.body, "Submitted by an owner"
        assert_select "form[action=?]", admin_reimbursements_endorse_my_budget_path(own.record_id), 0
      end

      test "a claim already endorsed (covering the amount) shows who endorsed it, no Endorse button" do
        ::Reimbursements::OwnerEndorsement.create!(expense_record_id: @pending.record_id,
                                                   budget_record_id: @owned.record_id,
                                                   endorsed_by_person_id: @owner.record_id,
                                                   endorsed_amount: BigDecimal("12.5"),
                                                   endorsed_at: Time.current)
        sign_in @user
        get :index

        assert_response :success
        assert_includes response.body, "Endorsed by Olive Owner"
        assert_select "form[action=?]", admin_reimbursements_endorse_my_budget_path(@pending.record_id), 0
      end

      test "a finance-overridden claim shows as cleared by finance" do
        ::Reimbursements::OwnerEndorsement.create!(expense_record_id: @pending.record_id,
                                                   budget_record_id: @owned.record_id,
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
        ::Reimbursements::OwnerEndorsement.create!(expense_record_id: @pending.record_id,
                                                   budget_record_id: @owned.record_id,
                                                   endorsed_by_person_id: @owner.record_id,
                                                   endorsed_amount: BigDecimal("5"),
                                                   endorsed_at: Time.current)
        sign_in @user
        get :index

        assert_response :success
        assert_select "form[action=?]", admin_reimbursements_endorse_my_budget_path(@pending.record_id)
        assert_not_includes response.body, "Endorsed by"
      end

      test "endorse records the current owner's endorsement" do
        sign_in @user

        assert_difference -> { ::Reimbursements::OwnerEndorsement.count }, 1 do
          post :endorse, params: { expense_id: @pending.record_id }
        end

        assert_redirected_to admin_reimbursements_my_budgets_path
        endorsement = ::Reimbursements::OwnerEndorsement.for_expense(@pending.record_id).first
        assert_equal @owner.record_id, endorsement.endorsed_by_person_id
        assert_equal @owned.record_id, endorsement.budget_record_id
        assert_equal BigDecimal("12.5"), endorsement.endorsed_amount, "snapshots the amount signed off"
        assert endorsement.owner_endorsement?
      end

      test "endorsing again is idempotent (any one owner suffices)" do
        sign_in @user
        ::Reimbursements::OwnerEndorsement.create!(expense_record_id: @pending.record_id,
                                                   budget_record_id: @owned.record_id,
                                                   endorsed_by_person_id: @stranger.record_id,
                                                   endorsed_at: Time.current)

        assert_no_difference -> { ::Reimbursements::OwnerEndorsement.count } do
          post :endorse, params: { expense_id: @pending.record_id }
        end
        assert_redirected_to admin_reimbursements_my_budgets_path
      end

      test "refuses to endorse a claim on a budget the person does not own" do
        other_budget_expense = create_reimbursements_expense(person: @other, budget: @not_owned,
                                                             status: ::Reimbursements::Status::PENDING)
        sign_in @user

        assert_no_difference -> { ::Reimbursements::OwnerEndorsement.count } do
          post :endorse, params: { expense_id: other_budget_expense.record_id }
        end
        assert_redirected_to admin_reimbursements_my_budgets_path
        assert_match(/only act on claims charged to budgets you own/i, flash[:alert])
      end

      test "withdraw removes the owner's endorsement, re-blocking finance" do
        ::Reimbursements::OwnerEndorsement.create!(expense_record_id: @pending.record_id,
                                                   budget_record_id: @owned.record_id,
                                                   endorsed_by_person_id: @owner.record_id,
                                                   endorsed_amount: BigDecimal("12.5"),
                                                   endorsed_at: Time.current)
        sign_in @user

        assert_difference -> { ::Reimbursements::OwnerEndorsement.count }, -1 do
          delete :withdraw, params: { expense_id: @pending.record_id }
        end
        assert_redirected_to admin_reimbursements_my_budgets_path
        assert_match(/withdrawn/i, flash[:notice])
      end

      test "reject sets the claim to Rejected with a reason" do
        sign_in @user

        patch :reject, params: { expense_id: @pending.record_id,
                                 rejection_reason: "Not a real business expense" }

        assert_redirected_to admin_reimbursements_my_budgets_path
        assert_match(/rejected/i, flash[:notice])
        @pending.reload
        assert_equal ::Reimbursements::Status::REJECTED, @pending.status
        assert_equal "Not a real business expense", @pending.rejection_reason
      end

      test "reject without a reason is refused" do
        sign_in @user

        patch :reject, params: { expense_id: @pending.record_id, rejection_reason: "  " }

        assert_match(/give a reason/i, flash[:alert])
        assert_equal ::Reimbursements::Status::PENDING, @pending.reload.status
      end

      test "reject is refused on a budget the owner does not own" do
        other = create_reimbursements_expense(person: @other, budget: @not_owned,
                                              status: ::Reimbursements::Status::PENDING)
        sign_in @user

        patch :reject, params: { expense_id: other.record_id, rejection_reason: "nope" }

        assert_match(/only act on claims charged to budgets you own/i, flash[:alert])
        assert_equal ::Reimbursements::Status::PENDING, other.reload.status
      end

      test "withdraw is refused on a claim the owner does not own" do
        other = create_reimbursements_expense(person: @other, budget: @not_owned,
                                              status: ::Reimbursements::Status::PENDING)
        sign_in @user

        delete :withdraw, params: { expense_id: other.record_id }

        assert_match(/only act on claims charged to budgets you own/i, flash[:alert])
      end
    end
  end
end
