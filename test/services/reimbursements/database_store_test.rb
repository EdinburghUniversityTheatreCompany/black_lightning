require "test_helper"

module Reimbursements
  # The AR-backed store is the single data gateway (built by
  # Reimbursements.build_store); these lock its public API and attribute
  # vocabulary.
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

    test "find_expense reads the row directly, unaffected by a stale memoized list" do
      store.expenses # memoize empty
      expense = Expense.create!(status: Status::PENDING)

      assert_equal expense.id, store.find_expense(expense.record_id).id
      assert_equal expense.id, store.find_expense!(expense.record_id).id
      assert_nil store.find_expense("999999")
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

      assert_raises(DatabaseStore::LastReceiptError) do
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

    test "link_offsetting_pair! stamps both legs and points them at each other" do
      accrual = store.create_actual!(nominal_code: "4000", narrative: "ACCRUAL", debit: 10)
      reversal = store.create_actual!(nominal_code: "4000", narrative: "REVERSAL", credit: 10)

      store.link_offsetting_pair!(accrual.record_id, reversal.record_id)

      accrual.reload
      reversal.reload
      assert_predicate accrual, :offset?
      assert_predicate reversal, :offset?
      assert_equal reversal.id, accrual.offset_of_id
      assert_equal accrual.id, reversal.offset_of_id
    end

    # Both rows survive an offset: finance needs the audit trail, so pairing
    # only ever stamps and cross-links, it never deletes.
    test "link_offsetting_pair! keeps both rows and refreshes the memoized list" do
      accrual = store.create_actual!(nominal_code: "4000", narrative: "ACCRUAL", debit: 10)
      reversal = store.create_actual!(nominal_code: "4000", narrative: "REVERSAL", credit: 10)
      store.eusa_actuals # memoize the pre-pairing list

      store.link_offsetting_pair!(accrual.record_id, reversal.record_id)

      assert_equal 2, EusaActual.count
      assert store.eusa_actuals.all?(&:offset?), "the memoized list is busted, not stale"
    end

    test "create_expense_for_actual! creates the expense already linked to the row" do
      actual = store.create_actual!(nominal_code: "4000", narrative: "Room hire", debit: 42)

      expense = store.create_expense_for_actual!(actual.record_id, status: Status::PAID)

      assert_equal [ expense.record_id ], actual.reload.linked_expense_ids
      assert_not_predicate actual, :convertible_to_expense?
    end

    # The convertibility guard lives INSIDE the writing transaction, so a caller
    # whose own check went stale cannot convert the same row twice.
    test "create_expense_for_actual! refuses a row that is already converted" do
      actual = store.create_actual!(nominal_code: "4000", narrative: "Room hire", debit: 42)
      store.create_expense_for_actual!(actual.record_id, status: Status::PAID)

      assert_raises(DatabaseStore::NotConvertibleError) do
        store.create_expense_for_actual!(actual.record_id, status: Status::PAID)
      end
      assert_equal 1, Expense.count, "the second attempt writes nothing"
    end

    test "create_expense_for_actual! refuses an offsetting leg" do
      actual = store.create_actual!(nominal_code: "4000", narrative: "Accrual", debit: 42)
      counterpart = store.create_actual!(nominal_code: "4000", narrative: "Reversal", credit: 42)
      store.link_offsetting_pair!(actual.record_id, counterpart.record_id)

      assert_raises(DatabaseStore::NotConvertibleError) do
        store.create_expense_for_actual!(actual.record_id, status: Status::PAID)
      end
      assert_equal 0, Expense.count, "an offsetting leg nets to zero, converting it invents spend"
    end

    test "create_offsetting_pair! imports both legs already cross-linked" do
      legs = store.create_offsetting_pair!(
        { nominal_code: "4000", narrative: "ACCRUAL", debit: 10 },
        { nominal_code: "4000", narrative: "REVERSAL", credit: 10 }
      )

      assert_equal 2, EusaActual.count
      assert legs.all?(&:offset?)
      assert_equal legs.last.id, legs.first.offset_of_id
      assert_equal legs.first.id, legs.last.offset_of_id
      assert store.eusa_actuals.all?(&:offset?), "the memoized list is busted, not stale"
    end

    test "unlink_offsetting_pair! clears both legs from either side" do
      accrual = store.create_actual!(nominal_code: "4000", narrative: "ACCRUAL", debit: 10)
      reversal = store.create_actual!(nominal_code: "4000", narrative: "REVERSAL", credit: 10)
      store.link_offsetting_pair!(accrual.record_id, reversal.record_id)

      store.unlink_offsetting_pair!(reversal.record_id)

      [ accrual, reversal ].each do |leg|
        leg.reload
        assert_not_predicate leg, :offset?
        assert_nil leg.offset_of_id
      end
      assert_equal 2, EusaActual.count, "unlinking never deletes a row"
      assert store.eusa_actuals.none?(&:offset?), "the memoized list is busted, not stale"
    end

    # A row pointing AT the one being cleared is cleared too, so a half-linked
    # row from an older import can't be left stamped with a dangling pointer.
    test "unlink_offsetting_pair! also clears a leg that only points at this one" do
      target = store.create_actual!(nominal_code: "4000", narrative: "TARGET", debit: 10)
      pointer = store.create_actual!(nominal_code: "4000", narrative: "POINTER", credit: 10)
      pointer.update!(offset_of_id: target.id, reconciliation_status: EusaActual::STATUS_OFFSET)
      target.update!(reconciliation_status: EusaActual::STATUS_OFFSET)

      store.unlink_offsetting_pair!(target.record_id)

      assert_not_predicate pointer.reload, :offset?
      assert_nil pointer.offset_of_id
      assert_not_predicate target.reload, :offset?
    end

    test "memoized lists refresh after bust_expenses!" do
      store.expenses
      Expense.create!(status: Status::PENDING)
      assert_empty store.expenses

      store.bust_expenses!
      assert_equal 1, store.expenses.size
    end

    # --- Budget overview grouping (Track G Phase 2) ------------------------

    test "budgets_by_nominal_code groups budgets under their code, sorted, blanks last" do
      props_a = Budget.create!(name: "Props A", nominal_code: "4000")
      props_b = Budget.create!(name: "Props B", nominal_code: "4000")
      travel = Budget.create!(name: "Travel", nominal_code: "4100")
      uncoded = Budget.create!(name: "Uncoded", nominal_code: "")

      grouped = store.budgets_by_nominal_code

      assert_equal [ "4000", "4100", "(none)" ].sort, grouped.keys.sort
      assert_equal [ props_a.id, props_b.id ].sort, grouped["4000"].map(&:id).sort
      assert_equal [ travel.id ], grouped["4100"].map(&:id)
      assert_equal [ uncoded.id ], grouped["(none)"].map(&:id)
    end

    # --- Preloads (what each reader costs) ---------------------------------

    test "budgets does not drag the actuals ledger in for a budget dropdown" do
      budget = Budget.create!(name: "Props", nominal_code: "4000")
      expense = Expense.create!(budget: budget, status: Status::PAID, amount_excl_vat: 10)
      EusaActual.create!(expense: expense, nominal_code: "4000", debit: 10)

      # The producer's new-expense form only needs names for a <select>; it must
      # not instantiate every expense and every ledger row to draw it.
      assert_no_queries_match(/reimbursements_eusa_actuals/i) { DatabaseStore.new.budgets }
      assert_no_queries_match(/reimbursements_expenses/i) { DatabaseStore.new.budgets }
      assert_no_queries_match(/reimbursements_eusa_actuals/i) { DatabaseStore.new.active_budgets }
    end

    test "budgets_with_actuals preloads so the EUSA rollup costs no per-budget query" do
      3.times do |i|
        budget = Budget.create!(name: "Props #{i}", nominal_code: "400#{i}")
        expense = Expense.create!(budget: budget, status: Status::PAID, amount_excl_vat: 10)
        EusaActual.create!(expense: expense, nominal_code: "400#{i}", debit: 10)
      end
      income = Budget.create!(name: "Ticket income", nominal_code: "8000", budget_type: "Income")
      EusaActual.create!(budget: income, nominal_code: "8000", credit: 50)

      loaded = DatabaseStore.new.budgets_with_actuals

      assert_queries_count(0) do
        assert_equal 4, loaded.size
        loaded.each { |budget| budget.eusa_actual_amount }
      end
    end

    test "expenses preloads payment details so a payee bank check costs no query" do
      pat = create_person(sort_code: "001122", account_number: "12345678")
      Expense.create!(person: pat, status: Status::PENDING, amount_excl_vat: 10)

      loaded = store.expenses

      # ReviewSupport.attention_summary asks this of every expense; without the
      # preload an end-of-year export pays one query per payee.
      assert_queries_count(0) { loaded.each(&:effective_has_bank_details?) }
    end

    test "unattributed_actuals are the rows no budget's figures account for" do
      props = Budget.create!(name: "Props", nominal_code: "4000")
      income = Budget.create!(name: "Ticket income", nominal_code: "8000", budget_type: "Income")
      expense = Expense.create!(budget: props, status: Status::PAID, amount_excl_vat: 10)

      # Counted by Props via its expense, and by the income budget directly.
      linked_expense = EusaActual.create!(nominal_code: "4000", narrative: "linked", debit: 10,
                                          expense: expense)
      linked_budget = EusaActual.create!(nominal_code: "8000", narrative: "income", credit: 50,
                                         budget: income)
      # Counted by nobody, even though 4000 *does* have a budget: linkage is what
      # a budget rollup can see, so this is exactly the invisible spend.
      on_budgeted_code = EusaActual.create!(nominal_code: "4000", narrative: "unlinked hire",
                                            debit: BigDecimal("1250"))
      no_budget_at_all = EusaActual.create!(nominal_code: "9999", narrative: "no budget", debit: 20)
      blank_code = EusaActual.create!(nominal_code: "", narrative: "no code", debit: 5)
      unlinked_credit = EusaActual.create!(nominal_code: "4000", narrative: "refund", credit: 30)

      unattributed = store.unattributed_actuals.map(&:id)

      assert_includes unattributed, on_budgeted_code.id
      assert_includes unattributed, no_budget_at_all.id
      assert_includes unattributed, blank_code.id, "a blank nominal code must not be suppressed"
      assert_includes unattributed, unlinked_credit.id
      assert_not_includes unattributed, linked_expense.id
      assert_not_includes unattributed, linked_budget.id
      # Sorted by nominal code (blank first, then numerically ascending) so
      # finance can see which budget a row probably belongs to.
      assert_equal [ blank_code.id, on_budgeted_code.id, unlinked_credit.id,
                     no_budget_at_all.id ], store.unattributed_actuals.map(&:id)
    end

    test "unattributed_actuals excludes both legs of an offsetting pair" do
      accrual = store.create_actual!(nominal_code: "4000", narrative: "ACCRUAL",
                                     debit: BigDecimal("4200"))
      reversal = store.create_actual!(nominal_code: "4000", narrative: "REVERSAL",
                                      credit: BigDecimal("4200"))
      store.link_offsetting_pair!(accrual.record_id, reversal.record_id)

      assert_empty store.unattributed_actuals,
                   "a correctly-offset accrual pair nets to zero, it is not unplanned spend"
    end

    # --- Budget updates (Track G Phase 3) ----------------------------------

    test "create_budget_update! records the shared update and one forecast per entry" do
      a = Budget.create!(name: "Props", nominal_code: "4000")
      b = Budget.create!(name: "Travel", nominal_code: "4100")
      user = users(:member)

      update = store.create_budget_update!(
        effective_date: Date.new(2026, 6, 1), note: "Budget meeting",
        created_by: user,
        forecasts: [ { budget_id: a.record_id, amount: BigDecimal("500") },
                     { budget_id: b.record_id, amount: BigDecimal("250") } ]
      )

      assert_equal Date.new(2026, 6, 1), update.effective_date
      assert_equal "Budget meeting", update.note
      assert_equal user.id, update.created_by_id
      assert_equal 2, update.forecasts.count
      # Each forecast carries the shared date + note and links back to the update.
      created = BudgetForecast.where(budget_update_id: update.id).order(:budget_id)
      assert_equal [ BigDecimal("500"), BigDecimal("250") ].sort, created.map(&:amount).sort
      assert created.all? { |f| f.date == Date.new(2026, 6, 1) && f.reason == "Budget meeting" }
      # The new forecast becomes each budget's current forecast.
      assert_equal BigDecimal("500"), Budget.find(a.id).current_forecast
    end

    test "create_budget_update! rolls back entirely if one forecast is invalid" do
      a = Budget.create!(name: "Props", nominal_code: "4000")

      assert_no_difference [ -> { BudgetUpdate.count }, -> { BudgetForecast.count } ] do
        assert_raises(ActiveRecord::RecordInvalid) do
          store.create_budget_update!(
            effective_date: Date.new(2026, 6, 1), note: "x", created_by: nil,
            forecasts: [ { budget_id: a.record_id, amount: BigDecimal("500") },
                         { budget_id: a.record_id, amount: nil } ] # amount required
          )
        end
      end
    end
  end
end
