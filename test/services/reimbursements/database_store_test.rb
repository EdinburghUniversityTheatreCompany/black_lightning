require "test_helper"

module Reimbursements
  # The AR-backed store's public API and attribute vocabulary.
  class DatabaseStoreTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    def store = @store ||= DatabaseStore.new

    test "expenses_for filters by payee and sorts newest first" do
      pat = create_reimbursements_person
      other = create_reimbursements_person(name: "Other", email: "other@example.com")
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
      assert_nil store.find_expense("999999")
    end

    test "person_by_email is case-insensitive and strips" do
      pat = create_reimbursements_person(email: "pat@example.com")
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
      alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")
      bob = create_reimbursements_person(name: "Bob", email: "bob@example.com")
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
      pat = create_reimbursements_person
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

    # Finance deletes budgets while producers hold the form open, and a raw InvalidForeignKey
    # would 500 and lose the claim (Honeybadger 134234926).
    test "a write naming a vanished budget raises BudgetGoneError and writes nothing" do
      pat = create_reimbursements_person
      expense = Expense.create!(status: Status::PENDING, amount: 5, description: "before")
      budget = Budget.create!(name: "Props")
      gone_id = budget.record_id
      budget.destroy!

      assert_raises(DatabaseStore::BudgetGoneError) do
        store.create_expense!(person_record_id: pat.record_id, budget_record_id: gone_id,
                              status: Status::PENDING, amount: BigDecimal("12.5"))
      end
      assert_equal 1, Expense.count, "nothing may be written"

      assert_raises(DatabaseStore::BudgetGoneError) do
        store.update_expense!(expense.record_id, budget_record_id: gone_id, description: "after")
      end
      assert_equal "before", expense.reload.description, "the whole update must roll back"
    end

    test "update_expense! drops nils, clears foreign_amount and honours an explicit budget clear" do
      budget = Budget.create!(name: "Props")
      expense = Expense.create!(status: Status::PENDING, budget: budget, amount: 5,
                                foreign_amount: BigDecimal("640"), foreign_currency: "EUR")

      # foreign_amount is the one money column a present-and-nil value clears; blanking it used
      # to be a silent no-op that looked like a save.
      store.update_expense!(expense.record_id, amount: nil, foreign_amount: nil, description: "kept")
      expense.reload
      assert_equal BigDecimal("5"), expense.amount, "amount keeps the 'nil means leave it' contract"
      assert_nil expense.foreign_amount
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
                                  sharepoint_backup_url: "https://sp/x",
                                  draft_message_id: "AAMkAG=")

      assert_equal "2026-05-13", batch.name # derived
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
      assert person.verified
      assert_equal "ok", person.notes
      assert_equal 1, PaymentDetails.count

      store.update_person!(person.record_id, verified: false)
      assert_not person.reload.verified
    end

    test "actuals: create, per-period lookup, and linking" do
      expense = Expense.create!(status: Status::PAID)
      budget = Budget.create!(name: "Props")

      actual = store.create_actual!(nominal_code: "4000", narrative: "BACS", debit: 10,
                                    period: "P1", expense_id: expense.id)
      assert_equal expense.id, actual.expense_id
      assert_nil actual.budget_id

      assert_equal [ actual.id ], store.actuals_for_period("P1").map(&:id)
      assert_empty store.actuals_for_period("P2")

      store.link_actual_to_budget!(actual.record_id, budget.record_id)
      assert_equal budget.id, EusaActual.find(actual.id).budget_id
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
      assert_equal 2, EusaActual.count, "pairing never deletes a row: finance needs the audit trail"
    end

    # The guard sits inside the transaction, so a stale caller check cannot convert a row twice.
    test "create_expense_for_actual! links the new expense and refuses a second conversion" do
      actual = store.create_actual!(nominal_code: "4000", narrative: "Room hire", debit: 42)

      expense = store.create_expense_for_actual!(actual.record_id, status: Status::PAID)
      assert_equal expense.id, actual.reload.expense_id

      assert_raises(DatabaseStore::NotConvertibleError) do
        store.create_expense_for_actual!(actual.record_id, status: Status::PAID)
      end
      assert_equal 1, Expense.count, "the second attempt writes nothing"
    end

    # The expense and its link commit together, or a failed link leaves the row still offering
    # "Create expense" and the next click double-counts the charge.
    test "create_expense_for_actual! writes nothing when the link fails" do
      failing = Class.new(DatabaseStore) { def link_actual_to_expense!(*) = raise("blip") }.new
      actual = failing.create_actual!(nominal_code: "4000", narrative: "Room hire", debit: 42)

      assert_no_difference -> { Expense.count } do
        assert_raises(RuntimeError) { failing.create_expense_for_actual!(actual.record_id, status: Status::PAID) }
      end
      assert_nil actual.reload.expense_id
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
    end

    # A row pointing at the cleared one is cleared too, so no half-linked row keeps a dangling
    # pointer.
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

    # --- Cache busting on every write --------------------------------------
    # One store serves a request, so a write that forgets its bust makes later reads render
    # pre-write figures. A missing bust leaves the same memoized array in place, so identity is
    # the check.
    test "every write busts the memoized list it affects" do
      person = create_reimbursements_person
      budget = Budget.create!(name: "Props", nominal_code: "4000")
      forecast = store.create_forecast!(budget_id: budget.record_id, amount: 100,
                                        date: Date.new(2026, 5, 1), reason: "initial")
      expense = Expense.create!(status: Status::SUBMITTED, person: person, budget: budget)
      draft = Expense.create!(status: Status::DRAFT, person: person)
      batch = Batch.create!(date_sent: Date.new(2026, 5, 13))
      accrual = EusaActual.create!(nominal_code: "4000", narrative: "ACCRUAL", debit: 10)
      reversal = EusaActual.create!(nominal_code: "4000", narrative: "REVERSAL", credit: 10)

      writes = [
        [ :budgets, "update_budget!", -> { store.update_budget!(budget.record_id, notes: "n") } ],
        [ :budgets, "update_forecast!",
          -> { store.update_forecast!(forecast.record_id, amount: 120, date: Date.new(2026, 5, 2), reason: "fix") } ],
        [ :budgets, "delete_forecast!", -> { store.delete_forecast!(forecast.record_id) } ],
        [ :budgets, "create_forecast!",
          -> { store.create_forecast!(budget_id: budget.record_id, amount: 400, date: Date.new(2026, 6, 1), reason: "r") } ],
        [ :budgets, "create_budget_update!",
          -> { store.create_budget_update!(effective_date: Date.new(2026, 6, 1), note: "n", created_by: nil, forecasts: [ { budget_id: budget.record_id, amount: BigDecimal("500") } ]) } ],
        [ :expenses, "create_expense!",
          -> { store.create_expense!(person_record_id: person.record_id, status: Status::PENDING) } ],
        [ :expenses, "attach_receipt!",
          -> { store.attach_receipt!(draft.record_id, filename: "d.pdf", content_type: "application/pdf", bytes: "%PDF") } ],
        [ :expenses, "remove_receipt!",
          -> { store.remove_receipt!(draft.record_id, draft.reload.receipts.sole.attachment_id) } ],
        [ :expenses, "update_expense!", -> { store.update_expense!(expense.record_id, amount: BigDecimal("42")) } ],
        [ :expenses, "revert_expense_to_approved!", -> { store.revert_expense_to_approved!(expense.record_id) } ],
        [ :expenses, "delete_expense!", -> { store.delete_expense!(draft.record_id) } ],
        [ :people, "create_person!", -> { store.create_person!(name: "New", email: "new@example.com") } ],
        [ :people, "update_person!", -> { store.update_person!(person.record_id, name: "Pat P") } ],
        [ :batches, "create_batch!", -> { store.create_batch!(date_sent: Date.new(2026, 6, 3)) } ],
        [ :batches, "update_batch!", -> { store.update_batch!(batch.record_id, producer_notifications_sent: true) } ],
        [ :batches, "delete_batch!", -> { store.delete_batch!(batch.record_id) } ],
        [ :eusa_actuals, "create_actual!", -> { store.create_actual!(nominal_code: "4000", narrative: "new", debit: 1) } ],
        [ :eusa_actuals, "link_actual_to_expense!",
          -> { store.link_actual_to_expense!(accrual.record_id, expense.record_id) } ],
        [ :eusa_actuals, "link_actual_to_budget!",
          -> { store.link_actual_to_budget!(accrual.record_id, budget.record_id) } ],
        [ :eusa_actuals, "link_offsetting_pair!",
          -> { store.link_offsetting_pair!(accrual.record_id, reversal.record_id) } ],
        [ :eusa_actuals, "unlink_offsetting_pair!",
          -> { store.unlink_offsetting_pair!(accrual.record_id) } ],
        [ :eusa_actuals, "create_offsetting_pair!",
          -> { store.create_offsetting_pair!({ nominal_code: "4000", narrative: "A2", debit: 5 }, { nominal_code: "4000", narrative: "R2", credit: 5 }) } ]
      ]

      writes.each do |list, label, write|
        before = store.public_send(list)
        write.call
        assert_not_same before, store.public_send(list),
                        "#{label} must bust the memoized #{list} list"
      end
    end

    # --- Budget overview grouping ------------------------------------------

    test "budgets_by_nominal_code groups budgets under their code, sorted, blanks last" do
      props_a = Budget.create!(name: "Props A", nominal_code: "4000")
      props_b = Budget.create!(name: "Props B", nominal_code: "4000")
      travel = Budget.create!(name: "Travel", nominal_code: "4100")
      uncoded = Budget.create!(name: "Uncoded", nominal_code: "")

      grouped = store.budgets_by_nominal_code

      assert_equal [ "4000", "4100", "(none)" ], grouped.keys
      assert_equal [ props_a.id, props_b.id ].sort, grouped["4000"].map(&:id).sort
      assert_equal [ travel.id ], grouped["4100"].map(&:id)
      assert_equal [ uncoded.id ], grouped["(none)"].map(&:id)
    end

    # --- Preloads (what each reader costs) ---------------------------------

    test "budgets does not drag the actuals ledger in for a budget dropdown" do
      budget = Budget.create!(name: "Props", nominal_code: "4000")
      expense = Expense.create!(budget: budget, status: Status::PAID, amount_excl_vat: 10)
      EusaActual.create!(expense: expense, nominal_code: "4000", debit: 10)

      # The producer's <select> needs names only, not every expense and ledger row.
      assert_no_queries_match(/reimbursements_(eusa_actuals|expenses)\b/i) { DatabaseStore.new.active_budgets }
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
      pat = create_reimbursements_person(sort_code: "001122", account_number: "12345678")
      Expense.create!(person: pat, status: Status::PENDING, amount_excl_vat: 10)

      loaded = store.expenses

      # attention_summary asks this of every expense; without the preload an export pays a query
      # per payee.
      assert_queries_count(0) { loaded.each(&:effective_has_bank_details?) }
    end

    test "unattributed_actuals are the rows no budget's figures account for" do
      props = Budget.create!(name: "Props", nominal_code: "4000")
      income = Budget.create!(name: "Ticket income", nominal_code: "8000", budget_type: "Income")
      expense = Expense.create!(budget: props, status: Status::PAID, amount_excl_vat: 10)

      # Counted by Props via its expense, and by the income budget directly.
      EusaActual.create!(nominal_code: "4000", narrative: "linked", debit: 10, expense: expense)
      EusaActual.create!(nominal_code: "8000", narrative: "income", credit: 50, budget: income)
      # Counted by nobody although 4000 has a budget: linkage, not nominal code, decides.
      on_budgeted_code = EusaActual.create!(nominal_code: "4000", narrative: "unlinked hire",
                                            debit: BigDecimal("1250"))
      no_budget_at_all = EusaActual.create!(nominal_code: "9999", narrative: "no budget", debit: 20)
      blank_code = EusaActual.create!(nominal_code: "", narrative: "no code", debit: 5)
      unlinked_credit = EusaActual.create!(nominal_code: "4000", narrative: "refund", credit: 30)
      # An offset pair nets to zero, so neither leg is unplanned spend.
      accrual = store.create_actual!(nominal_code: "4000", narrative: "ACCRUAL",
                                     debit: BigDecimal("4200"))
      reversal = store.create_actual!(nominal_code: "4000", narrative: "REVERSAL",
                                      credit: BigDecimal("4200"))
      store.link_offsetting_pair!(accrual.record_id, reversal.record_id)

      # Sorted by nominal code, blank first (a blank code must not be suppressed).
      assert_equal [ blank_code.id, on_budgeted_code.id, unlinked_credit.id,
                     no_budget_at_all.id ], store.unattributed_actuals.map(&:id)
    end

    # An apportioned row has no budget_id, so only the apportioned exclusion keeps it off the
    # card; undoing the split must put it back.
    test "an apportioned row is off the unattributed list until the split is removed" do
      budget = create_reimbursements_budget(name: "Show A", budget_type: "Income")
      actual = create_reimbursements_eusa_actual(credit: 900)
      store.apportion_actual!(actual.id, [ { budget_id: budget.id, amount: BigDecimal("900") } ])
      assert_not_includes store.unattributed_actuals.map(&:id), actual.id

      store.remove_apportionment!(actual.id)
      assert_includes store.unattributed_actuals.map(&:id), actual.id
    end

    # apportioned? reads an association: without the preload behind eusa_actuals_for_cost_centre
    # it fires a query per row.
    test "the unattributed list does not query per row for allocations" do
      3.times { |i| create_reimbursements_eusa_actual(credit: 100, narrative: "Payout #{i}") }
      fresh = DatabaseStore.new
      fresh.eusa_actuals # warm the one list read the card is built from

      assert_queries_count(0) { fresh.unattributed_actuals }
    end

    # --- Budget updates ----------------------------------------------------

    test "create_budget_update! records the shared update and one forecast per entry" do
      FinancialYear.create!(label: "Fringe 2026", active: true)
      draft = FinancialYear.create!(label: "Fringe 2027")
      a = Budget.create!(name: "Props", nominal_code: "4000")
      b = Budget.create!(name: "Travel", nominal_code: "4100")
      user = users(:member)

      update = scoped_store(draft).create_budget_update!(
        effective_date: Date.new(2026, 6, 1), note: "Budget meeting",
        created_by: user,
        forecasts: [ { budget_id: a.record_id, amount: BigDecimal("500") },
                     { budget_id: b.record_id, amount: BigDecimal("250") } ]
      )

      assert_equal Date.new(2026, 6, 1), update.effective_date
      assert_equal "Budget meeting", update.note
      assert_equal user.id, update.created_by_id
      assert_equal draft, update.financial_year, "stamps the year being viewed, not just the live one"
      created = BudgetForecast.where(budget_update_id: update.id).order(:budget_id)
      assert_equal [ BigDecimal("500"), BigDecimal("250") ].sort, created.map(&:amount).sort
      assert created.all? { |f| f.date == Date.new(2026, 6, 1) && f.reason == "Budget meeting" }
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

    # --- Financial-year scoping ---------------------------------------------

    def scoped_store(year) = DatabaseStore.new(financial_year: year)

    test "year scoping: budgets_for_year and budgets_with_actuals narrow, budgets does not" do
      this_year = FinancialYear.create!(label: "Fringe 2027")
      last_year = FinancialYear.create!(label: "Fringe 2026", active: true)
      mine = Budget.create!(name: "Props", financial_year: this_year)
      old = Budget.create!(name: "Old props", financial_year: last_year)
      scoped = scoped_store(this_year)

      assert_equal [ mine.id ], scoped.budgets_for_year.map(&:id)
      assert_equal [ mine.id ], scoped.budgets_with_actuals.map(&:id)
      # budgets is an id lookup: scoping it blanks the name on last year's claims.
      assert_includes scoped.budgets.map(&:id), old.id
    end

    test "budgets_for_year returns every budget when the store has no year" do
      year = FinancialYear.create!(label: "Fringe 2027")
      Budget.create!(name: "Props", financial_year: year)
      Budget.create!(name: "Unstamped")

      # Jobs and producer surfaces use an unscoped store and must keep seeing unstamped rows.
      assert_equal 2, store.budgets_for_year.size
    end

    test "active_budgets follows the ACTIVE year, not the selected one" do
      live = FinancialYear.create!(label: "Fringe 2026", active: true)
      draft = FinancialYear.create!(label: "Fringe 2027")
      live_budget = Budget.create!(name: "Props", active: true, financial_year: live)
      Budget.create!(name: "Next year props", active: true, financial_year: draft)

      # Submitters file against the live year; a finance user browsing next year's draft must not.
      assert_equal [ live_budget.id ], scoped_store(draft).active_budgets.map(&:id)
    end

    test "budget_updates are scoped to the store's year" do
      this_year = FinancialYear.create!(label: "Fringe 2027")
      last_year = FinancialYear.create!(label: "Fringe 2026", active: true)
      mine = BudgetUpdate.create!(effective_date: Date.new(2027, 1, 1), financial_year: this_year)
      BudgetUpdate.create!(effective_date: Date.new(2026, 1, 1), financial_year: last_year)

      assert_equal [ mine.id ], scoped_store(this_year).budget_updates.map(&:id)
    end

    # --- Cost-centre scoping -------------------------------------------------

    def centre_store(centre) = DatabaseStore.new(cost_centre: centre)

    def second_cost_centre = create_second_reimbursements_cost_centre

    test "cost-centre scoping: budgets_for_year and budgets_with_actuals narrow, budgets and active_budgets do not" do
      fringe = CostCentre.default
      mine = Budget.create!(name: "Props", cost_centre: fringe)
      theirs = Budget.create!(name: "Termtime props", active: true, cost_centre: second_cost_centre)
      unplaced = Budget.create!(name: "Unplaced")
      scoped = centre_store(fringe)

      # Same leniency as year scoping: a row from before cost centres must not vanish.
      assert_equal [ mine.id, unplaced.id ].sort, scoped.budgets_for_year.map(&:id).sort
      assert_equal [ mine.id, unplaced.id ].sort, scoped.budgets_with_actuals.map(&:id).sort
      # budgets is an id lookup; active_budgets is the submitter picker, which spans centres.
      assert_includes scoped.budgets.map(&:id), theirs.id
      assert_includes scoped.active_budgets.map(&:id), theirs.id
    end

    test "the money path owns an unplaced claim once, not once per centre" do
      fringe = CostCentre.default
      termtime = second_cost_centre
      mine = Expense.create!(status: Status::APPROVED,
                             budget: Budget.create!(name: "Props", cost_centre: fringe))
      unplaced = Expense.create!(status: Status::APPROVED)
      theirs = Expense.create!(status: Status::APPROVED,
                               budget: Budget.create!(name: "Termtime props", cost_centre: termtime))

      # The screens' filter resolves a claim's centre through its budget and shows an unplaced
      # claim under both centres: safe, it pays nobody. expenses itself is an unscoped id lookup.
      assert_equal [ mine.id, unplaced.id ].sort,
                   centre_store(fringe).expenses_for_cost_centre.map(&:id).sort
      assert_includes centre_store(termtime).expenses_for_cost_centre.map(&:id), unplaced.id
      assert_includes centre_store(fringe).expenses.map(&:id), theirs.id

      # Build Batch must not: two centres selecting one claim build it into two live EUSA drafts
      # (limits_concurrency is per centre, so the builds do not serialise) and EUSA pays twice.
      assert_includes store.expenses_owned_by_cost_centre(fringe).map(&:id), unplaced.id
      assert_not_includes store.expenses_owned_by_cost_centre(termtime).map(&:id), unplaced.id
      assert_includes store.expenses_owned_by_cost_centre(termtime).map(&:id), theirs.id
    end

    test "the money path refuses to answer without a cost centre" do
      # "No centre" cannot mean "every centre" on a path that pays people.
      assert_raises(ArgumentError) { store.expenses_owned_by_cost_centre(nil) }
    end

    test "eusa_actuals_for_cost_centre and unattributed_actuals scope on the row's own centre, eusa_actuals does not" do
      mine = EusaActual.create!(narrative: "Ours", debit: 10, cost_centre: CostCentre.default)
      theirs = EusaActual.create!(narrative: "Theirs", debit: 10, cost_centre: second_cost_centre)
      unplaced = EusaActual.create!(narrative: "Legacy", debit: 10)
      scoped = centre_store(CostCentre.default)

      assert_equal [ mine.id, unplaced.id ].sort, scoped.eusa_actuals_for_cost_centre.map(&:id).sort
      assert_equal [ mine.id, unplaced.id ].sort, scoped.unattributed_actuals.map(&:id).sort
      # eusa_actuals is the reconcile dedup pool and stays whole.
      assert_includes scoped.eusa_actuals.map(&:id), theirs.id
    end

    test "batches_for_cost_centre reads each batch's centre off its expenses" do
      fringe = CostCentre.default
      termtime = second_cost_centre
      mine = Batch.create!(name: "Fringe run")
      theirs = Batch.create!(name: "Termtime run")
      empty = Batch.create!(name: "No expenses yet")
      Expense.create!(status: Status::SUBMITTED, batch: mine,
                      budget: Budget.create!(name: "Props", cost_centre: fringe))
      Expense.create!(status: Status::SUBMITTED, batch: theirs,
                      budget: Budget.create!(name: "Termtime props", cost_centre: termtime))

      ids = centre_store(fringe).batches_for_cost_centre.map(&:id)
      assert_includes ids, mine.id
      assert_includes ids, empty.id
      assert_not_includes ids, theirs.id
    end

    test "import_budgets! adopts an unplaced budget into the importing centre" do
      termtime = second_cost_centre
      unplaced = Budget.create!(name: "Venue hire")
      placed = Budget.create!(name: "Props", cost_centre: CostCentre.default)

      store.import_budgets!(
        creates: [], revisions: [], owner_syncs: [], note: "Import", created_by: nil,
        adoptions: [ { budget_id: unplaced.record_id, cost_centre: termtime },
                     { budget_id: placed.record_id, cost_centre: termtime } ]
      )

      assert_equal termtime.id, unplaced.reload.cost_centre_id
      # Never re-homes a line another pot owns, even if asked.
      assert_equal CostCentre.default.id, placed.reload.cost_centre_id
    end

    # --- import_budgets! -----------------------------------------------------

    test "import_budgets! creates budgets stamped with the year and cost centre" do
      year = FinancialYear.create!(label: "Fringe 2027")
      cost_centre = CostCentre.default
      alice = Person.create!(name: "Alice", email: "alice@example.com")

      result = scoped_store(year).import_budgets!(
        creates: [ { name: "Props", nominal_code: "4000", budget_type: "Expense",
                     initial_budget: BigDecimal("1200"), notes: "", active: true,
                     financial_year: year, cost_centre: cost_centre,
                     owner_ids: [ alice.id.to_s ] } ],
        revisions: [], owner_syncs: [], note: "Committee budget", created_by: nil
      )

      budget = Budget.find_by(name: "Props")
      assert_equal year, budget.financial_year
      assert_equal cost_centre, budget.cost_centre
      assert_equal BigDecimal("1200"), budget.initial_budget
      assert_equal [ alice.record_id ], budget.owner_ids
      assert_equal 1, result.created
      assert_equal 0, result.revised
    end

    test "import_budgets! logs revisions as one budget update, leaving initial_budget alone" do
      year = FinancialYear.create!(label: "Fringe 2027", active: true)
      budget = Budget.create!(name: "Props", nominal_code: "4000",
                              initial_budget: BigDecimal("1000"), financial_year: year)

      result = scoped_store(year).import_budgets!(
        creates: [], revisions: [ { budget_id: budget.record_id, amount: BigDecimal("1200") } ],
        owner_syncs: [], note: "Revised budget", created_by: nil
      )

      budget.reload
      assert_equal BigDecimal("1000"), budget.initial_budget
      assert_equal BigDecimal("1200"), budget.current_forecast
      assert_equal 1, BudgetUpdate.count
      assert_equal "Revised budget", BudgetUpdate.sole.note
      assert_equal year, BudgetUpdate.sole.financial_year
      assert_equal 1, result.revised
    end

    # The sheet is the committee's route for revising a show's agreed total: it lands as a forecast
    # on the AREA under the same BudgetUpdate as the line revisions, and the area's initial_budget
    # stays write-once so drift is still measurable.
    test "import_budgets! logs a revised area total as an area forecast in the same update" do
      year = FinancialYear.create!(label: "Fringe 2027", active: true)
      area = Area.create!(name: "Cogito", initial_budget: BigDecimal("1000"), financial_year: year)
      budget = Budget.create!(name: "Marketing", nominal_code: "432320",
                              initial_budget: BigDecimal("400"), financial_year: year, area: area)

      result = scoped_store(year).import_budgets!(
        creates: [], revisions: [ { budget_id: budget.record_id, amount: BigDecimal("450") } ],
        area_revisions: [ { area_id: area.record_id, amount: BigDecimal("1200") } ],
        owner_syncs: [], note: "Revised at the budget meeting", created_by: nil
      )

      assert_equal 1, BudgetUpdate.count, "one meeting, one update across both levels"
      forecasts = BudgetUpdate.sole.forecasts
      assert_equal [ BigDecimal("450"), BigDecimal("1200") ], forecasts.map(&:amount).sort
      area_forecast = forecasts.find { |forecast| forecast.area_id.present? }
      assert_equal area.id, area_forecast.area_id
      assert_nil area_forecast.budget_id, "a forecast belongs to a budget OR an area, never both"

      area.reload
      assert_equal BigDecimal("1000"), area.initial_budget
      assert_equal BigDecimal("1200"), area.projected_amount
      assert_equal 1, result.area_revised
    end

    test "import_budgets! writes an update for an area revision even with no line revisions" do
      year = FinancialYear.create!(label: "Fringe 2027", active: true)
      area = Area.create!(name: "Cogito", initial_budget: BigDecimal("1000"), financial_year: year)

      scoped_store(year).import_budgets!(
        creates: [], revisions: [],
        area_revisions: [ { area_id: area.record_id, amount: BigDecimal("1200") } ],
        owner_syncs: [], note: "x", created_by: nil
      )

      assert_equal 1, BudgetUpdate.count
      assert_equal BigDecimal("1200"), area.reload.projected_amount
    end

    test "import_budgets! rolls the whole sheet back when one line fails" do
      year = FinancialYear.create!(label: "Fringe 2027")
      good = { name: "Props", nominal_code: "4000", budget_type: "Expense", active: true,
               financial_year: year, cost_centre: nil, owner_ids: [] }
      # A blank name fails Budget's presence validation.
      bad = good.merge(name: "")

      assert_no_difference -> { Budget.count } do
        assert_raises(ActiveRecord::RecordInvalid) do
          scoped_store(year).import_budgets!(creates: [ good, bad ], revisions: [],
                                             owner_syncs: [], note: "x", created_by: nil)
        end
      end
    end

    test "import_budgets! writes no budget update when nothing was revised" do
      year = FinancialYear.create!(label: "Fringe 2027")

      scoped_store(year).import_budgets!(
        creates: [ { name: "Props", nominal_code: "4000", budget_type: "Expense", active: true,
                     financial_year: year, cost_centre: nil, owner_ids: [] } ],
        revisions: [], owner_syncs: [], note: "x", created_by: nil
      )

      assert_equal 0, BudgetUpdate.count
    end

    test "import_budgets! puts a create in an area named by the sheet (created first) or passed by id" do
      year = FinancialYear.create!(label: "Fringe 2027")
      cost_centre = CostCentre.default
      existing = create_reimbursements_area(name: "Improverts", cost_centre: cost_centre,
                                            financial_year: year)

      result = assert_difference -> { Area.count }, 1 do
        scoped_store(year).import_budgets!(
          creates: [ { name: "Cogito: Marketing", nominal_code: "4000", budget_type: "Expense",
                       active: true, financial_year: year, cost_centre: cost_centre,
                       owner_ids: [], area_name: "Cogito" },
                     { name: "Improverts: Props", nominal_code: "4001", budget_type: "Expense",
                       active: true, financial_year: year, cost_centre: cost_centre,
                       owner_ids: [], area_id: existing.record_id } ],
          revisions: [], owner_syncs: [], note: "x", created_by: nil,
          area_creates: [ { name: "Cogito", cost_centre: cost_centre, financial_year: year } ]
        )
      end

      assert_equal Area.find_by(name: "Cogito").id, Budget.find_by(name: "Cogito: Marketing").area_id
      assert_equal existing.id, Budget.find_by(name: "Improverts: Props").area_id
      assert_equal 1, result.areas_created
    end

    # Shares #resolve_area with creates, so a re-import (every line matched, nothing created)
    # still puts lines into the area the sheet creates.
    test "import_budgets! re-homes budgets into an area it creates and out of the area they were in" do
      year = FinancialYear.create!(label: "Fringe 2027")
      cost_centre = CostCentre.default
      improverts = create_reimbursements_area(name: "Improverts", cost_centre: cost_centre,
                                              financial_year: year)
      cogito = create_reimbursements_area(name: "Cogito", cost_centre: cost_centre,
                                          financial_year: year)
      unplaced = Budget.create!(name: "Panto: Marketing", financial_year: year,
                                cost_centre: cost_centre)
      moved = Budget.create!(name: "Cogito: Marketing", financial_year: year,
                             cost_centre: cost_centre, area: improverts)

      result = scoped_store(year).import_budgets!(
        creates: [], revisions: [], owner_syncs: [], note: "x", created_by: nil,
        area_creates: [ { name: "Panto", cost_centre: cost_centre, financial_year: year } ],
        re_homes: [ { budget_id: unplaced.record_id, area_name: "Panto" },
                    { budget_id: moved.record_id, area_id: cogito.record_id } ]
      )

      assert_equal Area.find_by(name: "Panto").id, unplaced.reload.area_id
      assert_equal cogito.id, moved.reload.area_id
      assert_equal 2, result.re_homed
    end

    test "import_budgets! re-syncs owners on budgets that already existed" do
      year = FinancialYear.create!(label: "Fringe 2027")
      alice = Person.create!(name: "Alice", email: "alice@example.com")
      budget = Budget.create!(name: "Props", financial_year: year)

      scoped_store(year).import_budgets!(
        creates: [], revisions: [],
        owner_syncs: [ { budget_id: budget.record_id, owner_ids: [ alice.id.to_s ] } ],
        note: "x", created_by: nil
      )

      assert_equal [ alice.record_id ], budget.reload.owner_ids
    end

    # --- Area owners: the sheet adds and never removes -----------------------
    # A blank cell says nothing, so removal stays hand-work on the area form.

    test "import_budgets! unions the sheet's owners into an area, removing nobody" do
      year = FinancialYear.create!(label: "Fringe 2027")
      alice = Person.create!(name: "Alice", email: "alice@example.com")
      bob = Person.create!(name: "Bob", email: "bob@example.com")
      area = create_reimbursements_area(name: "Cogito", cost_centre: CostCentre.default,
                                        financial_year: year)
      area.sync_owner_ids!([ bob.id ])

      result = scoped_store(year).import_budgets!(
        creates: [], revisions: [], owner_syncs: [], note: "x", created_by: nil,
        area_owner_syncs: [ { area_id: area.record_id, owner_ids: [ alice.record_id ] } ]
      )

      assert_equal [ alice.record_id, bob.record_id ].sort, area.reload.owner_ids.sort
      assert_equal 1, result.area_owners_synced
    end

    test "import_budgets! gives an area it created in the same run its owners" do
      year = FinancialYear.create!(label: "Fringe 2027")
      cost_centre = CostCentre.default
      alice = Person.create!(name: "Alice", email: "alice@example.com")

      scoped_store(year).import_budgets!(
        creates: [], revisions: [], owner_syncs: [], note: "x", created_by: nil,
        area_creates: [ { name: "Cogito", cost_centre: cost_centre, financial_year: year } ],
        area_owner_syncs: [ { area_name: "Cogito", owner_ids: [ alice.record_id ] } ]
      )

      assert_equal [ alice.record_id ], Area.find_by(name: "Cogito").owner_ids
    end

    # Owners are grouped by the area each line names, ticked or not, so an area every re-home was
    # unticked out of is never created and has nothing to own.
    test "import_budgets! skips an area owner sync for an area it never created" do
      year = FinancialYear.create!(label: "Fringe 2027")
      alice = Person.create!(name: "Alice", email: "alice@example.com")

      result = assert_no_difference -> { AreaOwner.count } do
        scoped_store(year).import_budgets!(
          creates: [], revisions: [], owner_syncs: [], note: "x", created_by: nil,
          area_owner_syncs: [ { area_name: "Cogito", owner_ids: [ alice.record_id ] } ]
        )
      end

      assert_equal 0, result.area_owners_synced
    end

    # The property, not the branch: an empty list means "the sheet named nobody", never "remove
    # everyone". Two defences hold it jointly (the union makes the list a superset, and the
    # `any?` guard keeps a bare list from Area#sync_owner_ids!'s WHERE 1=1), so a test of the
    # guard alone could not fail.
    test "add_area_owners! with an empty list removes nobody" do
      bob = Person.create!(name: "Bob", email: "bob@example.com")
      area = create_reimbursements_area(name: "Cogito")
      area.sync_owner_ids!([ bob.id ])

      store.add_area_owners!(area.record_id, [])

      assert_equal [ bob.record_id ], area.reload.owner_ids
    end

    # --- import_expenses! ----------------------------------------------------

    test "import_expenses! creates one claim per row, in one transaction" do
      pat = create_reimbursements_person
      budget = Budget.create!(name: "Props")

      created = store.import_expenses!(rows: [
        expense_row(pat, budget, key: "OLD-1"), expense_row(pat, budget, key: "OLD-2")
      ])

      assert_equal 2, created.size
      assert_equal %w[OLD-1 OLD-2], Expense.order(:id).pluck(:import_key)
    end

    test "import_expenses! writes nothing at all when one row fails" do
      pat = create_reimbursements_person
      budget = Budget.create!(name: "Props")
      Expense.create!(status: Status::PAID, import_key: "OLD-2")

      assert_no_difference -> { Expense.count } do
        assert_raises ActiveRecord::RecordNotUnique do
          store.import_expenses!(rows: [
            expense_row(pat, budget, key: "OLD-1"), expense_row(pat, budget, key: "OLD-2")
          ])
        end
      end
    end

    # Numbered rows go first, or MAX+1 walks into a number the sheet is about to claim.
    test "import_expenses! honours the sheet's expense numbers without colliding" do
      pat = create_reimbursements_person
      budget = Budget.create!(name: "Props")

      store.import_expenses!(rows: [
        expense_row(pat, budget, key: "OLD-1"),
        expense_row(pat, budget, key: "OLD-2").merge(auto_number: 1)
      ])

      assert_equal [ 1, 2 ], Expense.order(:auto_number).pluck(:auto_number)
    end

    # nil means "assign one"; a number somebody handed over is never retried past a collision.
    test "create_expense! numbers a claim given a nil auto_number and raises on a handed number that is taken" do
      first = store.create_expense!(status: Status::PAID, auto_number: nil)
      assert_predicate first.auto_number, :present?

      assert_raises(ActiveRecord::RecordNotUnique) do
        store.create_expense!(status: Status::PAID, auto_number: first.auto_number)
      end
    end

    def expense_row(person, budget, key:)
      { person_record_id: person.record_id, budget_record_id: budget.record_id,
        status: Status::PAID, amount: BigDecimal("12.50"),
        amount_excl_vat: BigDecimal("12.50"), description: "Fake blood",
        payment_reference: "PROPS PAT", expense_type: Expense::TYPE_REIMBURSEMENT,
        payment_method: Expense::PAYMENT_METHOD_UK_BACS, import_key: key }
    end

    # --- settle_expense_from_actual! ----------------------------------------
    # Shared by the reconcile apply and the manual link on the Actuals index.

    def settle_setup(international:, amount: BigDecimal("230.00"))
      budget = Budget.create!(name: "Insurance", nominal_code: "432540")
      attrs = { budget: budget, status: Status::SUBMITTED, amount: amount,
                amount_excl_vat: amount, description: "Festival insurance" }
      if international
        attrs.merge!(payment_method: Expense::PAYMENT_METHOD_INTERNATIONAL,
                     foreign_amount: BigDecimal("266.69"),
                     foreign_currency: Expense::CURRENCY_EUR)
      end
      expense = Expense.create!(**attrs)
      actual = EusaActual.create!(nominal_code: "432540", narrative: "Ausland GmbH",
                                  debit: BigDecimal("236.10"), date: Date.new(2026, 5, 20))
      [ expense, actual ]
    end

    # The stored amount is finance's estimate; uncorrected, every rollup quotes it forever.
    test "settling an international claim links the row and corrects its amount to what the bank charged" do
      expense, actual = settle_setup(international: true)

      store.settle_expense_from_actual!(actual.record_id, expense.record_id,
                                        payment_date: Date.new(2026, 5, 20),
                                        gbp_charged: BigDecimal("236.10"))

      settled = expense.reload
      assert_equal BigDecimal("236.10"), settled.amount
      assert_equal BigDecimal("236.10"), settled.amount_excl_vat
      assert_equal Status::PAID, settled.status
      assert_equal Date.new(2026, 5, 20), settled.payment_confirmed_date
      assert_equal expense.id, actual.reload[:expense_id]
    end

    # A UK amount is what the producer spent, not an estimate.
    test "settling a UK claim leaves its amount alone" do
      expense, actual = settle_setup(international: false)

      store.settle_expense_from_actual!(actual.record_id, expense.record_id,
                                        payment_date: Date.new(2026, 5, 20),
                                        gbp_charged: BigDecimal("236.10"))

      settled = expense.reload
      assert_equal BigDecimal("230.00"), settled.amount, "a UK amount is not an estimate"
      assert_equal Status::PAID, settled.status
    end

    # Both callers filter first; this is the refusal for the next one that forgets.
    test "settling refuses a claim nobody agreed to pay or one already settled, and writes nothing" do
      other_row = EusaActual.create!(nominal_code: "432540", narrative: "Earlier run",
                                     debit: BigDecimal("230.00"))
      {
        "a draft" => { status: Status::DRAFT },
        "a rejected claim" => { status: Status::REJECTED },
        "a Paid claim with a payment date" => { status: Status::PAID,
                                                payment_confirmed_date: Date.new(2026, 5, 1) },
        "a Paid claim another row settled" => { status: Status::PAID, other_row: true }
      }.each do |label, attrs|
        expense, actual = settle_setup(international: false)
        other_row.update!(expense_id: expense.id) if attrs.delete(:other_row)
        expense.update!(attrs)
        before = expense.reload.attributes.slice("status", "payment_confirmed_date")

        error = assert_raises(DatabaseStore::NotSettleableError, label) do
          store.settle_expense_from_actual!(actual.record_id, expense.record_id,
                                            payment_date: Date.new(2026, 5, 20))
        end
        assert_equal expense.status, error.status, label
        assert_nil actual.reload[:expense_id], label
        assert_equal before, expense.reload.attributes.slice("status", "payment_confirmed_date"), label
      end
    end

    # An imported Paid claim with no payment date is still waiting for its EUSA row.
    test "settling still takes a Paid claim no row or payment date has settled yet" do
      expense, actual = settle_setup(international: false)
      expense.update!(status: Status::PAID)

      store.settle_expense_from_actual!(actual.record_id, expense.record_id,
                                        payment_date: Date.new(2026, 5, 20))

      assert_equal Date.new(2026, 5, 20), expense.reload.payment_confirmed_date
      assert_equal expense.id, actual.reload[:expense_id]
    end

    # --- Areas -----------------------------------------------------------

    test "areas is unscoped; areas_for_year narrows by year and centre and keeps unplaced areas" do
      year = FinancialYear.create!(label: "Fringe 2027")
      other = create_second_reimbursements_cost_centre
      mine = create_reimbursements_area(name: "Cogito", cost_centre: CostCentre.default,
                                        financial_year: year)
      theirs = create_reimbursements_area(name: "Panto", cost_centre: other, financial_year: year)
      unplaced = create_reimbursements_area(name: "Unplaced")
      scoped = DatabaseStore.new(financial_year: year, cost_centre: CostCentre.default)

      assert_includes scoped.areas, theirs, "areas is an id->record lookup and must not be narrowed"
      assert_equal [ mine.id, unplaced.id ].sort, scoped.areas_for_year.map(&:id).sort
      assert_equal 3, store.areas_for_year.size, "an unscoped store sees every area"
    end

    test "find_area reads the row directly, unaffected by a stale memoized list" do
      store.areas # memoize empty
      area = create_reimbursements_area(name: "Cogito")

      assert_equal area.id, store.find_area(area.record_id).id
      assert_nil store.find_area("999999")
    end

    # The area edit page's figures read each line's expenses and forecasts.
    test "find_area preloads each budget line's expenses and forecasts" do
      area = create_reimbursements_area(name: "Cogito")
      budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)
      create_reimbursements_expense(budget: budget, receipt: false)
      budget.forecasts.create!(amount: 100, date: Date.current, reason: "x")

      found = store.find_area(area.record_id)
      line = found.budgets.first

      assert_predicate found.budgets, :loaded?
      assert_predicate found.association(:owners), :loaded?
      assert_predicate line.association(:expenses), :loaded?
      assert_predicate line.association(:forecasts), :loaded?
    end

    test "create_area! writes the given columns and busts the memoized lists" do
      year = FinancialYear.create!(label: "Fringe 2027")
      cost_centre = CostCentre.default
      store.areas # memoize both lists, so a same-request relist must see the new area
      store.areas_for_year

      area = store.create_area!(name: "Cogito", initial_budget: BigDecimal("500"),
                                notes: "Autumn show", active: true,
                                cost_centre: cost_centre, financial_year: year)

      assert_equal "Cogito", area.name
      assert_equal BigDecimal("500"), area.initial_budget
      assert_equal "Autumn show", area.notes
      assert_equal cost_centre, area.cost_centre
      assert_equal year, area.financial_year
      assert_includes store.areas.map(&:id), area.id
      assert_includes store.areas_for_year.map(&:id), area.id
    end

    test "sync_area_owners! diff-syncs the owners join table" do
      alice = Person.create!(name: "Alice", email: "alice@example.com")
      bob = Person.create!(name: "Bob", email: "bob@example.com")
      area = create_reimbursements_area(name: "Cogito")
      area.sync_owner_ids!([ alice.id ])
      store.areas # memoize the stale owner list in

      # A multi-checkbox posts a blank hidden default; to_i would make it 0 and raise
      # InvalidForeignKey.
      store.sync_area_owners!(area.record_id, [ "", bob.id.to_s ])

      assert_equal [ bob.record_id ], area.reload.owner_ids
      assert_equal [ bob.record_id ], store.areas.find { |a| a.id == area.id }.owner_ids
    end

    test "areas preloads owners and its budgets' expenses and forecasts" do
      alice = Person.create!(name: "Alice", email: "alice@example.com")
      2.times do |i|
        area = create_reimbursements_area(name: "Show #{i}")
        area.sync_owner_ids!([ alice.id ])
        budget = create_reimbursements_budget(name: "Props #{i}", area: area)
        Expense.create!(budget: budget, status: Status::PAID, amount_excl_vat: 10)
        BudgetForecast.create!(budget: budget, amount: 100, date: Date.current, reason: "x")
      end

      loaded = DatabaseStore.new.areas

      # Without the preload an areas index N+1s per budget per area.
      assert_queries_count(0) do
        assert_equal 2, loaded.size
        loaded.each do |area|
          area.owner_ids
          area.committed_amount
          area.allocated
        end
      end
    end
  end
end
