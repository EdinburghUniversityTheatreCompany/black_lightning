require "test_helper"

module Admin
  module Reimbursements
  class ReconcileControllerTest < ActionController::TestCase
    include ReimbursementsTestHelpers

    HEADER = "Nominal\tCost Centre\tRef\tDate\tPeriod\tNarrative\tNarrative 1\tDebit\tCredit\tNet".freeze

    setup do
      finance = Role.create!(name: "Business Manager")
      finance.permissions << Permission.create(action: "manage", subject_class: "reimbursements_finance")
      users(:member).add_role("Business Manager")
      @user = users(:member)

      # A Submitted expense that a debit row should match: nominal 439999,
      # excl-VAT 123.45, submitted to EUSA within 14 days of the actuals date.
      @person = airtable_person_record(id: "recPer1", name: "Alice Producer", email: "alice@example.com")
      @budget = airtable_budget_record(id: "recBud1", name: "Props", nominal_code: "439999")
      @income = airtable_budget_record(id: "recBudInc", name: "Ticket income", nominal_code: "250000")
                .tap { |r| r["fields"][FIELD_IDS[:budgets][:budget_type]] = "Income" }

      @expense = airtable_expense_record(
        id: "recExp1", payee_id: "recPer1", budget_id: "recBud1",
        amount: 123.45, amount_excl_vat: 123.45,
        overrides: {
          FIELD_IDS[:expenses][:status] => "Submitted",
          FIELD_IDS[:expenses][:submitted_to_eusa_date] => "2026-05-10"
        }
      )

      rebuild_store
    end

    teardown do
      BaseController.store_builder = -> { ::Reimbursements::Store.new }
    end

    def rebuild_store(expenses: nil, people: nil, budgets: nil, eusa_actuals: [])
      @store, @client = build_fake_store(
        expenses: expenses || [ @expense ],
        people: people || [ @person ],
        budgets: budgets || [ @budget, @income ],
        eusa_actuals: eusa_actuals
      )
      BaseController.store_builder = -> { @store }
    end

    def debit_row(nominal: "439999", date: "13/05/2026", narrative: "Alice Producer", debit: "123.45")
      "#{nominal}\tF40\tBACS001\t#{date}\t03\t#{narrative}\tShow\t#{debit}\t\t#{debit}"
    end

    def credit_row(nominal: "250000", narrative: "Box office", credit: "500.00")
      "#{nominal}\tF40\tBACS002\t13/05/2026\t03\t#{narrative}\tTickets\t\t#{credit}\t-#{credit}"
    end

    # --- Auth gating -------------------------------------------------------

    test "requires sign-in" do
      get :show
      assert_redirected_to new_user_session_path
    end

    test "denies members without the finance permission" do
      sign_in users(:committee)
      get :show
      assert_response :forbidden
    end

    test "the producer portal permission alone does not grant finance access" do
      producer = Role.create!(name: "Producer")
      producer.permissions << Permission.create(action: "access", subject_class: "reimbursements")
      other = users(:member_with_phone_number)
      other.add_role("Producer")
      sign_in other

      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row}", source_month: "2026-05" }

      assert_response :forbidden
    end

    # --- Step 1: show ------------------------------------------------------

    test "show renders the paste form" do
      sign_in @user
      get :show

      assert_response :success
      assert_includes response.body, "Paste actuals data"
    end

    # --- Step 2: preview / parse + dedup + match ---------------------------

    test "preview rejects a malformed source month" do
      sign_in @user
      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row}", source_month: "May" }

      assert_response :success
      assert_includes response.body, "YYYY-MM"
    end

    test "preview matches a debit row to a submitted expense" do
      sign_in @user
      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row}", source_month: "2026-05" }

      assert_response :success
      assert_equal 1, assigns(:matched_debits).size
      row, expense = assigns(:matched_debits).first
      assert_equal "recExp1", expense.record_id
      assert_equal BigDecimal("123.45"), row.debit
      assert_empty assigns(:unmatched_rows)
    end

    test "preview matches a credit row to an income budget" do
      sign_in @user
      post :preview, params: { pasted_text: "#{HEADER}\n#{credit_row}", source_month: "2026-05" }

      assert_response :success
      assert_equal 1, assigns(:matched_credits).size
      _row, budget = assigns(:matched_credits).first
      assert_equal "recBudInc", budget.record_id
    end

    test "preview surfaces an unmatched debit when nothing matches" do
      sign_in @user
      post :preview, params: {
        pasted_text: "#{HEADER}\n#{debit_row(nominal: '999999')}", source_month: "2026-05"
      }

      assert_response :success
      assert_empty assigns(:matched_debits)
      assert_equal 1, assigns(:unmatched_rows).size
    end

    test "preview skips rows already imported for the month" do
      existing = airtable_eusa_actual_record(
        id: "recActDup", nominal_code: "439999", narrative: "Alice Producer",
        debit: 123.45, source_month: "2026-05"
      )
      rebuild_store(eusa_actuals: [ existing ])
      sign_in @user

      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row}", source_month: "2026-05" }

      assert_response :success
      assert_equal 1, assigns(:skipped_rows).size
      assert_empty assigns(:new_rows)
    end

    test "one expense is claimed by at most one debit row" do
      sign_in @user
      two_rows = "#{HEADER}\n#{debit_row}\n#{debit_row(date: '14/05/2026')}"
      post :preview, params: { pasted_text: two_rows, source_month: "2026-05" }

      assert_response :success
      assert_equal 1, assigns(:matched_debits).size
      assert_equal 1, assigns(:unmatched_rows).size, "the second row can't reclaim the same expense"
    end

    # --- Step 3: apply -----------------------------------------------------

    test "apply creates actuals, links them, flips the expense to Paid, and emails" do
      sign_in @user

      assert_emails 1 do
        post :apply, params: { pasted_text: "#{HEADER}\n#{debit_row}", source_month: "2026-05" }
      end

      assert_response :success
      # One EUSA Actuals row created, then linked to the expense.
      created_tables = @client.created.map(&:first)
      assert_equal [ :eusa_actuals ], created_tables
      link_update = @client.updated.find { |t, _id, f| t == :eusa_actuals }
      assert_equal [ "recExp1" ], link_update.last[FIELD_IDS[:eusa_actuals][:linked_expense]]
      # Expense flipped to Paid with a payment-confirmed date.
      paid_update = @client.updated.find { |t, id, _f| t == :expenses && id == "recExp1" }
      assert_equal "Paid", paid_update.last[FIELD_IDS[:expenses][:status]]
      assert_equal "2026-05-13", paid_update.last[FIELD_IDS[:expenses][:payment_confirmed_date]]
      assert_equal 1, assigns(:expenses_paid)
    end

    test "apply links a matched credit to its budget without emailing" do
      sign_in @user

      assert_no_emails do
        post :apply, params: { pasted_text: "#{HEADER}\n#{credit_row}", source_month: "2026-05" }
      end

      assert_response :success
      budget_link = @client.updated.find { |t, _id, f| t == :eusa_actuals }
      assert_equal [ "recBudInc" ], budget_link.last[FIELD_IDS[:eusa_actuals][:linked_budget]]
      assert_equal 1, assigns(:credits_linked)
    end

    test "apply saves an unmatched row and marks no expense Paid" do
      sign_in @user

      assert_no_emails do
        post :apply, params: {
          pasted_text: "#{HEADER}\n#{debit_row(nominal: '999999')}", source_month: "2026-05"
        }
      end

      assert_response :success
      assert_equal 1, assigns(:unmatched_saved)
      assert_equal 0, assigns(:expenses_paid)
      assert_empty @client.updated.select { |t, _id, _f| t == :expenses }
    end

    test "apply skips a producer with no email" do
      no_email = airtable_person_record(id: "recPer1", name: "Alice Producer", email: "")
      rebuild_store(people: [ no_email ])
      sign_in @user

      assert_no_emails do
        post :apply, params: { pasted_text: "#{HEADER}\n#{debit_row}", source_month: "2026-05" }
      end

      assert_response :success
      assert_equal 1, assigns(:expenses_paid)
    end

    test "apply redirects when the pasted text is missing" do
      sign_in @user
      post :apply, params: { pasted_text: "", source_month: "2026-05" }

      assert_redirected_to admin_reimbursements_reconciliation_path
    end
  end
  end
end
