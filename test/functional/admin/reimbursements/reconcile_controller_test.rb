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

      # "You've been paid" emails now go through the Graph notifier; inject a real
      # Notifier over a recording FakeGraphClient so tests assert the send.
      @graph = FakeGraphClient.new
      ReconcileController.notifier_builder =
        ->(mailbox:) { ::Reimbursements::Notifier.new(mailbox: mailbox, graph: @graph) }
    end

    teardown do
      BaseController.store_builder = -> { ::Reimbursements::Store.new }
      ReconcileController.notifier_builder =
        ->(mailbox:) { ::Reimbursements::Notifier.new(mailbox: mailbox) }
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

    def debit_row(nominal: "439999", date: "13/05/2026", period: "03", narrative: "Alice Producer",
                  debit: "123.45")
      "#{nominal}\tF40\tBACS001\t#{date}\t#{period}\t#{narrative}\tShow\t#{debit}\t\t#{debit}"
    end

    def credit_row(nominal: "250000", period: "03", narrative: "Box office", credit: "500.00")
      "#{nominal}\tF40\tBACS002\t13/05/2026\t#{period}\t#{narrative}\tTickets\t\t#{credit}\t-#{credit}"
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

      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row}" }

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

    test "preview matches a debit row to a submitted expense" do
      sign_in @user
      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row}" }

      assert_response :success
      assert_equal 1, assigns(:matched_debits).size
      row, expense = assigns(:matched_debits).first
      assert_equal "recExp1", expense.record_id
      assert_equal BigDecimal("123.45"), row.debit
      assert_empty assigns(:unmatched_rows)
    end

    test "preview matches a credit row to an income budget" do
      sign_in @user
      post :preview, params: { pasted_text: "#{HEADER}\n#{credit_row}" }

      assert_response :success
      assert_equal 1, assigns(:matched_credits).size
      _row, budget = assigns(:matched_credits).first
      assert_equal "recBudInc", budget.record_id
    end

    test "preview surfaces an unmatched debit when nothing matches" do
      sign_in @user
      post :preview, params: {
        pasted_text: "#{HEADER}\n#{debit_row(nominal: '999999')}"
      }

      assert_response :success
      assert_empty assigns(:matched_debits)
      assert_equal 1, assigns(:unmatched_rows).size
    end

    test "preview re-renders show with an alert on a malformed paste (missing header columns)" do
      sign_in @user
      bad_header = "Nominal\tCost Centre\tRef\tDate\tNarrative\tNarrative 1\tDebit\tCredit\tNet" # no Period
      post :preview, params: { pasted_text: "#{bad_header}\n#{debit_row}" }

      assert_response :success
      assert_includes response.body, "Could not parse actuals"
    end

    test "preview alerts when the paste has only a header row, no data" do
      sign_in @user
      post :preview, params: { pasted_text: HEADER }

      assert_response :success
      assert_includes response.body, "No data rows found"
    end

    test "apply redirects with an alert on a malformed paste" do
      sign_in @user
      bad_header = "Nominal\tCost Centre\tRef\tDate\tNarrative\tNarrative 1\tDebit\tCredit\tNet" # no Period
      post :apply, params: { pasted_text: "#{bad_header}\n#{debit_row}" }

      assert_redirected_to admin_reimbursements_reconciliation_path
      assert_match(/Could not parse the actuals/, flash[:alert])
      assert_empty @client.created
    end

    test "an expense with a payment_confirmed_date but no linked actual is excluded from matching" do
      already_paid = airtable_expense_record(
        id: "recExp1", payee_id: "recPer1", budget_id: "recBud1",
        amount: 123.45, amount_excl_vat: 123.45,
        overrides: {
          FIELD_IDS[:expenses][:status] => "Submitted",
          FIELD_IDS[:expenses][:submitted_to_eusa_date] => "2026-05-10",
          FIELD_IDS[:expenses][:payment_confirmed_date] => "2026-05-01"
        }
      )
      rebuild_store(expenses: [ already_paid ]) # no eusa_actuals linked
      sign_in @user

      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row}" }

      assert_response :success
      assert_empty assigns(:matched_debits), "already-paid-by-another-route expenses must not be re-matched"
      assert_equal 1, assigns(:unmatched_rows).size
    end

    test "preview skips rows already imported for the same period" do
      existing = airtable_eusa_actual_record(
        id: "recActDup", nominal_code: "439999", period: "03", narrative: "Alice Producer",
        debit: 123.45
      )
      rebuild_store(eusa_actuals: [ existing ])
      sign_in @user

      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row(period: '03')}" }

      assert_response :success
      assert_equal 1, assigns(:skipped_rows).size
      assert_empty assigns(:new_rows)
    end

    test "preview re-imports a matching row when it was imported under a different period" do
      # Same nominal/narrative/amount, but the imported copy is in period 02, so
      # the pasted period-03 row is new (dedup is scoped per EUSA period).
      existing = airtable_eusa_actual_record(
        id: "recActP2", nominal_code: "439999", period: "02", narrative: "Alice Producer",
        debit: 123.45
      )
      rebuild_store(eusa_actuals: [ existing ])
      sign_in @user

      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row(period: '03')}" }

      assert_response :success
      assert_empty assigns(:skipped_rows)
      assert_equal 1, assigns(:new_rows).size
    end

    test "a single paste dedups each period independently" do
      # Period 03 already imported; period 04 is not. Re-pasting both keeps only
      # the period-04 row.
      existing = airtable_eusa_actual_record(
        id: "recActP3", nominal_code: "439999", period: "03", narrative: "Alice Producer",
        debit: 123.45
      )
      rebuild_store(eusa_actuals: [ existing ])
      sign_in @user

      two_rows = "#{HEADER}\n#{debit_row(period: '03')}\n#{debit_row(period: '04')}"
      post :preview, params: { pasted_text: two_rows }

      assert_response :success
      assert_equal 1, assigns(:skipped_rows).size
      assert_equal "03", assigns(:skipped_rows).first.period
      assert_equal 1, assigns(:new_rows).size
      assert_equal "04", assigns(:new_rows).first.period
    end

    test "one expense is claimed by at most one debit row" do
      sign_in @user
      two_rows = "#{HEADER}\n#{debit_row}\n#{debit_row(date: '14/05/2026')}"
      post :preview, params: { pasted_text: two_rows }

      assert_response :success
      assert_equal 1, assigns(:matched_debits).size
      assert_equal 1, assigns(:unmatched_rows).size, "the second row can't reclaim the same expense"
    end

    # --- Step 3: apply -----------------------------------------------------

    test "apply creates actuals, links them, flips the expense to Paid, and emails" do
      sign_in @user

      post :apply, params: { pasted_text: "#{HEADER}\n#{debit_row}" }

      mail = @graph.send_mails.sole
      assert_equal "reimbursements@bedlamfringe.co.uk", mail[:mailbox]
      assert_equal [ "alice@example.com" ], mail[:to]
      assert_match(/EUSA has paid/, mail[:subject])

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

      post :apply, params: { pasted_text: "#{HEADER}\n#{credit_row}" }

      assert_empty @graph.send_mails
      assert_response :success
      budget_link = @client.updated.find { |t, _id, f| t == :eusa_actuals }
      assert_equal [ "recBudInc" ], budget_link.last[FIELD_IDS[:eusa_actuals][:linked_budget]]
      assert_equal 1, assigns(:credits_linked)
    end

    test "apply saves an unmatched row and marks no expense Paid" do
      sign_in @user

      post :apply, params: {
        pasted_text: "#{HEADER}\n#{debit_row(nominal: '999999')}"
      }

      assert_empty @graph.send_mails
      assert_response :success
      assert_equal 1, assigns(:unmatched_saved)
      assert_equal 0, assigns(:expenses_paid)
      assert_empty @client.updated.select { |t, _id, _f| t == :expenses }
    end

    test "apply skips a producer with no email" do
      no_email = airtable_person_record(id: "recPer1", name: "Alice Producer", email: "")
      rebuild_store(people: [ no_email ])
      sign_in @user

      post :apply, params: { pasted_text: "#{HEADER}\n#{debit_row}" }

      assert_empty @graph.send_mails
      assert_response :success
      assert_equal 1, assigns(:expenses_paid)
    end

    test "a Graph send failure does not break the reconciliation" do
      @graph.fail_send = true
      sign_in @user

      post :apply, params: { pasted_text: "#{HEADER}\n#{debit_row}" }

      assert_response :success
      # The expense is still marked Paid even though the notification send failed.
      paid_update = @client.updated.find { |t, id, _f| t == :expenses && id == "recExp1" }
      assert_equal "Paid", paid_update.last[FIELD_IDS[:expenses][:status]]
      assert_equal 1, assigns(:expenses_paid)
    end

    test "an already-reconciled expense is not re-matched or re-emailed by a later paste" do
      # recExp1 was already paid in an earlier period and linked to an imported
      # actual. A later/overlapping export carries a near-identical row (same
      # nominal/amount, matching date, but a slightly different narrative) so the
      # per-period dedup does NOT skip it. The re-pay guard must exclude the
      # already-linked expense so it can't be re-matched, re-paid, or re-emailed.
      paid = airtable_expense_record(
        id: "recExp1", payee_id: "recPer1", budget_id: "recBud1",
        amount: 123.45, amount_excl_vat: 123.45,
        overrides: {
          FIELD_IDS[:expenses][:status] => "Paid",
          FIELD_IDS[:expenses][:submitted_to_eusa_date] => "2026-05-10"
        }
      )
      linked_actual = airtable_eusa_actual_record(
        id: "recActLinked", nominal_code: "439999", period: "02",
        narrative: "Alice Producer OLD", debit: 123.45, linked_expense: [ "recExp1" ]
      )
      rebuild_store(expenses: [ paid ], eusa_actuals: [ linked_actual ])
      sign_in @user

      post :apply, params: {
        pasted_text: "#{HEADER}\n#{debit_row(narrative: 'Alice Producer NEW')}"
      }

      assert_response :success
      assert_empty @graph.send_mails, "must not re-email a producer for an already-reconciled expense"
      assert_equal 0, assigns(:expenses_paid)
      assert_equal 1, assigns(:unmatched_saved)
      # The expense itself is left untouched — no second flip-to-Paid write.
      assert_empty @client.updated.select { |t, id, _f| t == :expenses && id == "recExp1" }
    end

    test "a mid-batch row failure doesn't abort the rest, and is surfaced instead of hidden" do
      second_expense = airtable_expense_record(
        id: "recExp2", payee_id: "recPer1", budget_id: "recBud1",
        amount: 55.00, amount_excl_vat: 55.00,
        overrides: {
          FIELD_IDS[:expenses][:status] => "Submitted",
          FIELD_IDS[:expenses][:submitted_to_eusa_date] => "2026-05-10",
          FIELD_IDS[:expenses][:nominal_code_override] => "555555"
        }
      )
      rebuild_store(expenses: [ @expense, second_expense ])
      # recExp2's link write fails (simulating a transient blip after its
      # Actual record was already created); recExp1's row is untouched.
      linked_field = FIELD_IDS[:eusa_actuals][:linked_expense]
      fail_update_record_when(@client) { |table, _record_id, fields| table == :eusa_actuals && fields[linked_field] == [ "recExp2" ] }
      sign_in @user

      post :apply, params: {
        pasted_text: "#{HEADER}\n#{debit_row}\n#{debit_row(nominal: '555555', narrative: 'Alice Producer', debit: '55.00')}"
      }

      assert_response :success
      # recExp1 committed fully (Paid + emailed); recExp2's failure didn't
      # abort it, and doesn't leave a silent "all good" report either.
      assert_equal 1, assigns(:expenses_paid)
      assert_equal [ "alice@example.com" ], @graph.send_mails.sole[:to]
      assert_nil @client.updated.find { |t, id, _f| t == :expenses && id == "recExp2" }
      assert_match(/expense #.*blip/i, assigns(:reconciliation_errors).sole)
      assert_match(/hit a problem/i, response.body)
    end

    test "a failed credit row is not counted in credits_linked" do
      linked_field = FIELD_IDS[:eusa_actuals][:linked_budget]
      fail_update_record_when(@client) { |table, _record_id, fields| table == :eusa_actuals && fields.key?(linked_field) }
      sign_in @user

      post :apply, params: { pasted_text: "#{HEADER}\n#{credit_row}" }

      assert_response :success
      assert_equal 0, assigns(:credits_linked), "a row whose link write failed must not count as linked"
      assert_match(/budget Ticket income.*blip/i, assigns(:reconciliation_errors).sole)
    end

    test "apply redirects when the pasted text is missing" do
      sign_in @user
      post :apply, params: { pasted_text: "" }

      assert_redirected_to admin_reimbursements_reconciliation_path
    end
  end
  end
end
