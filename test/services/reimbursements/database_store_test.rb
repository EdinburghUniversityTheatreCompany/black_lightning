require "test_helper"

module Reimbursements
  # The AR-backed store must honour the Airtable store's public API and
  # attribute vocabulary exactly — it is swapped in by flipping
  # REIMBURSEMENTS_BACKEND, with zero caller changes.
  class DatabaseStoreTest < ActiveSupport::TestCase
    def store = @store ||= DatabaseStore.new

    def create_person(name: "Pat", email: "pat@example.com", sort_code: nil, account_number: nil)
      person = Person.create!(name: name, email: email)
      if sort_code || account_number
        person.create_payment_details!(sort_code: sort_code.to_s, account_number: account_number.to_s)
      end
      person
    end

    test "expenses_for filters by payee and sorts newest first" do
      pat = create_person
      other = create_person(name: "Other", email: "other@example.com")
      old = Expense.create!(status: Status::PENDING, person: pat, submitted_at: 2.days.ago)
      new = Expense.create!(status: Status::PENDING, person: pat, submitted_at: 1.hour.ago)
      Expense.create!(status: Status::PENDING, person: other)

      assert_equal [ new.id, old.id ], store.expenses_for(pat.record_id).map(&:id)
      assert_empty store.expenses_for("")
    end

    test "find_expense! folds a row created after the list was memoized" do
      store.expenses # memoize empty
      expense = Expense.create!(status: Status::PENDING)

      assert_nil store.find_expense(expense.record_id)
      assert_equal expense.id, store.find_expense!(expense.record_id).id
      assert_equal expense.id, store.find_expense(expense.record_id).id
    end

    test "person_by_email is case-insensitive and strips" do
      pat = create_person(email: "pat@example.com")
      assert_equal pat.id, store.person_by_email("  PAT@Example.COM ").id
      assert_nil store.person_by_email("")
    end

    test "active_budgets excludes inactive and income, sorted by name" do
      b = Budget.create!(name: "B-Props", active: true)
      Budget.create!(name: "Hidden", active: false)
      Budget.create!(name: "Grant", budget_type: "Income")
      a = Budget.create!(name: "A-Costumes", active: true)

      assert_equal [ a.id, b.id ], store.active_budgets.map(&:id)
    end

    test "update_budget! updates columns and syncs owners" do
      budget = Budget.create!(name: "Props")
      alice = create_person(name: "Alice", email: "alice@example.com")
      bob = create_person(name: "Bob", email: "bob@example.com")
      budget.owners << alice

      store.update_budget!(budget.record_id, name: "Props 2", notes: "n",
                           initial_budget: 50, owner_ids: [ bob.record_id ])

      budget.reload
      assert_equal "Props 2", budget.name
      assert_equal BigDecimal("50"), budget.initial_budget
      assert_equal [ bob.record_id ], budget.owner_ids
    end

    test "forecast lifecycle: create, list newest-first, update, delete" do
      budget = Budget.create!(name: "Props")
      first = store.create_forecast!(budget_id: budget.id, amount: 100,
                                     date: Date.new(2026, 5, 1), reason: "initial")
      second = store.create_forecast!(budget_id: budget.id, amount: 150,
                                      date: Date.new(2026, 6, 1), reason: "revised")

      assert_equal [ second.id, first.id ], store.budget_forecasts(budget.id).map(&:id)
      assert_equal [], store.budget_forecasts("")

      store.update_forecast!(first.record_id, amount: 120, date: Date.new(2026, 5, 2), reason: "fix")
      assert_equal BigDecimal("120"), BudgetForecast.find(first.id).amount

      store.delete_forecast!(first.record_id)
      assert_not BudgetForecast.exists?(first.id)
    end

    test "create_expense! speaks the store vocabulary and stamps the year" do
      year = FinancialYear.create!(label: "Fringe 2026", active: true)
      pat = create_person
      budget = Budget.create!(name: "Props")

      expense = store.create_expense!(
        person_record_id: pat.record_id, budget_record_id: budget.record_id,
        status: Status::PENDING, amount: BigDecimal("12.5"),
        amount_excl_vat: BigDecimal("10.42"), description: "Fake blood",
        payment_reference: nil, sharepoint_receipt_urls: [ "https://sp/a", "https://sp/b" ]
      )

      assert_equal pat, expense.person
      assert_equal budget, expense.budget
      assert_equal year, expense.financial_year
      assert_equal [ "https://sp/a", "https://sp/b" ], expense.sharepoint_receipt_urls
      assert expense.submitted_at.present?
      assert_nil expense[:payment_reference]
    end

    test "update_expense! drops nils but honours an explicit budget clear" do
      budget = Budget.create!(name: "Props")
      expense = Expense.create!(status: Status::PENDING, budget: budget, amount: 5)

      store.update_expense!(expense.record_id, amount: nil, description: "kept")
      expense.reload
      assert_equal BigDecimal("5"), expense.amount
      assert_equal "kept", expense.description
      assert_equal budget, expense.budget

      store.update_expense!(expense.record_id, budget_record_id: "")
      assert_nil expense.reload.budget
    end

    test "receipt attach and remove, guarding the last receipt on a non-draft" do
      expense = Expense.create!(status: Status::PENDING)
      store.attach_receipt!(expense.record_id, filename: "r.pdf",
                            content_type: "application/pdf", bytes: "%PDF")
      receipt = expense.reload.receipts.sole

      assert_raises(Store::LastReceiptError) do
        store.remove_receipt!(expense.record_id, receipt.attachment_id)
      end

      draft = Expense.create!(status: Status::DRAFT)
      store.attach_receipt!(draft.record_id, filename: "d.pdf",
                            content_type: "application/pdf", bytes: "%PDF")
      store.remove_receipt!(draft.record_id, draft.reload.receipts.sole.attachment_id)
      assert_empty draft.reload.receipts
    end

    test "revert_expense_to_approved! unlinks the batch and clears offload bookkeeping" do
      batch = Batch.create!(date_sent: Date.new(2026, 5, 13))
      expense = Expense.create!(status: Status::SUBMITTED, batch: batch,
                                submitted_to_eusa_date: Date.new(2026, 5, 13),
                                receipts_offloaded: true, producer_notified: true,
                                sharepoint_receipt_urls: "https://sp/a")

      store.revert_expense_to_approved!(expense.record_id)

      expense.reload
      assert_equal Status::APPROVED, expense.status
      assert_nil expense.batch
      assert_nil expense.submitted_to_eusa_date
      assert_not expense.receipts_offloaded
      assert_empty expense.sharepoint_receipt_urls
      assert expense.producer_notified, "a rebuild must not re-email the producer"
    end

    test "batch lifecycle mirrors BatchProcessor's writes" do
      batch = store.create_batch!(date_sent: Date.new(2026, 5, 13),
                                  notes: "BACS SharePoint: https://sp/x",
                                  eusa_draft_created: true,
                                  sharepoint_backup_url: "https://sp/x",
                                  draft_message_id: "AAMkAG=")

      assert_equal "2026-05-13", batch.name # derived, like the Airtable formula
      assert batch.eusa_draft_created
      assert_equal batch.id, store.find_batch_by_draft_message_id("AAMkAG=").id
      assert_nil store.find_batch_by_draft_message_id("")

      store.update_batch!(batch.record_id, producer_notifications_sent: true)
      assert Batch.find(batch.id).producer_notifications_sent

      store.delete_batch!(batch.record_id)
      assert_not Batch.exists?(batch.id)
    end

    test "update_person! routes bank fields to PaymentDetails" do
      person = store.create_person!(name: "Pat", email: "pat@example.com")

      store.update_person!(person.record_id, name: "Pat P", sort_code: "80-22-60",
                           account_number: "12345678", verified: true, notes: "ok")

      person.reload
      assert_equal "Pat P", person.name
      assert_equal "80-22-60", person.sort_code
      assert_equal "12345678", person.account_number
      assert person.verified?
      assert_equal "ok", person.notes
      assert_equal 1, PaymentDetails.count

      store.update_person!(person.record_id, verified: false)
      assert_not person.reload.verified?
    end

    test "actuals: create with linked ids, per-period lookup, and linking" do
      expense = Expense.create!(status: Status::PAID)
      budget = Budget.create!(name: "Props")

      actual = store.create_actual!(nominal_code: "4000", narrative: "BACS", debit: 10,
                                    period: "P1", linked_expense_ids: [ expense.record_id ],
                                    linked_budget_ids: [])
      assert_equal [ expense.record_id ], actual.linked_expense_ids
      assert_empty actual.linked_budget_ids

      assert_equal [ actual.id ], store.actuals_for_period("P1").map(&:id)
      assert_empty store.actuals_for_period("P2")

      store.link_actual_to_budget!(actual.record_id, budget.record_id)
      assert_equal [ budget.record_id ], EusaActual.find(actual.id).linked_budget_ids
    end

    test "memoized lists refresh after bust_expenses!" do
      store.expenses
      Expense.create!(status: Status::PENDING)
      assert_empty store.expenses

      store.bust_expenses!
      assert_equal 1, store.expenses.size
    end
  end
end
