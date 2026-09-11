require "test_helper"

module Reimbursements
  # The AR-backed store is the single data gateway (built by
  # Reimbursements.build_store); these lock its public API and attribute
  # vocabulary.
  class DatabaseStoreTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

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

    # Belt and braces under ExpenseForm's offerable-budget rule. Finance deletes
    # budgets while producers hold the submission form open, so the row can go
    # between the form's check and this insert — and a raw
    # ActiveRecord::InvalidForeignKey is a 500 that loses the whole claim
    # (Honeybadger 134234926). Named, so the controller can re-render the form.
    test "create_expense! raises BudgetGoneError when the budget vanished" do
      pat = create_person
      budget = Budget.create!(name: "Props")
      gone_id = budget.record_id
      budget.destroy!

      assert_raises(DatabaseStore::BudgetGoneError) do
        store.create_expense!(person_record_id: pat.record_id, budget_record_id: gone_id,
                              status: Status::PENDING, amount: BigDecimal("12.5"))
      end
      assert_equal 0, Expense.count, "nothing may be written"
    end

    test "update_expense! raises BudgetGoneError when the budget vanished" do
      expense = Expense.create!(status: Status::PENDING, amount: 5, description: "before")
      budget = Budget.create!(name: "Props")
      gone_id = budget.record_id
      budget.destroy!

      assert_raises(DatabaseStore::BudgetGoneError) do
        store.update_expense!(expense.record_id, budget_record_id: gone_id, description: "after")
      end
      assert_equal "before", expense.reload.description, "the whole update must roll back"
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
                                  sharepoint_backup_url: "https://sp/x",
                                  draft_message_id: "AAMkAG=")

      assert_equal "2026-05-13", batch.name # derived, like the Airtable formula
      # Derived from the draft message id, not sent by the caller and not a column.
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

    # --- Cache busting on every write --------------------------------------
    # One store serves a whole request, so a write that forgets its bust_*! makes
    # every later read in that request render pre-write figures — the operator
    # saves a budget and the page redraws with the old number. These read the
    # memoized list first, write, then re-read and assert the FRESH figures.

    test "update_budget! and the forecast writes refresh the memoized budgets" do
      budget = Budget.create!(name: "Props", nominal_code: "4000", initial_budget: 100)
      store.budgets # memoize the pre-write list

      store.update_budget!(budget.record_id, initial_budget: 250)
      assert_equal BigDecimal("250"), store.budgets.sole.initial_budget,
                   "update_budget! must bust the memoized budgets"

      store.create_forecast!(budget_id: budget.record_id, amount: 400,
                             date: Date.new(2026, 6, 1), reason: "revised")
      assert_equal BigDecimal("400"), store.budgets.sole.current_forecast,
                   "create_forecast! must bust the memoized budgets"
    end

    test "create_budget_update! refreshes the memoized budgets" do
      budget = Budget.create!(name: "Props", nominal_code: "4000")
      store.budgets

      store.create_budget_update!(
        effective_date: Date.new(2026, 6, 1), note: "Budget meeting", created_by: users(:member),
        forecasts: [ { budget_id: budget.record_id, amount: BigDecimal("500") } ]
      )

      assert_equal BigDecimal("500"), store.budgets.sole.current_forecast
    end

    test "update_person! refreshes the memoized people" do
      person = store.create_person!(name: "Pat", email: "pat@example.com")
      store.people # memoize the pre-write list

      store.update_person!(person.record_id, name: "Pat Producer", account_number: "66374958")

      refreshed = store.people.sole
      assert_equal "Pat Producer", refreshed.name, "update_person! must bust the memoized people"
      assert_equal "66374958", refreshed.account_number
    end

    test "update_expense! refreshes the memoized expenses" do
      expense = Expense.create!(status: Status::PENDING, amount: 5)
      store.expenses # memoize the pre-write list

      store.update_expense!(expense.record_id, amount: BigDecimal("42"))

      assert_equal BigDecimal("42"), store.expenses.sole.amount,
                   "update_expense! must bust the memoized expenses"
    end

    # The sweep: 22 bust_*! call sites, one row per mutator. A missing bust
    # leaves the very same memoized array object in place, so identity is the
    # honest uniform check — the content assertions above pin the figures.
    test "every write busts the memoized list it affects" do
      person = create_person
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
        [ :expenses, "create_expense!",
          -> { store.create_expense!(person_record_id: person.record_id, status: Status::PENDING) } ],
        [ :expenses, "attach_receipt!",
          -> { store.attach_receipt!(draft.record_id, filename: "d.pdf", content_type: "application/pdf", bytes: "%PDF") } ],
        [ :expenses, "remove_receipt!",
          -> { store.remove_receipt!(draft.record_id, draft.reload.receipts.sole.attachment_id) } ],
        [ :expenses, "revert_expense_to_approved!", -> { store.revert_expense_to_approved!(expense.record_id) } ],
        [ :expenses, "delete_expense!", -> { store.delete_expense!(draft.record_id) } ],
        [ :people, "create_person!", -> { store.create_person!(name: "New", email: "new@example.com") } ],
        [ :batches, "create_batch!", -> { store.create_batch!(date_sent: Date.new(2026, 6, 3)) } ],
        [ :batches, "update_batch!", -> { store.update_batch!(batch.record_id, producer_notifications_sent: true) } ],
        [ :batches, "delete_batch!", -> { store.delete_batch!(batch.record_id) } ],
        [ :eusa_actuals, "create_actual!", -> { store.create_actual!(nominal_code: "4000", narrative: "new", debit: 1) } ],
        [ :eusa_actuals, "link_actual_to_expense!",
          -> { store.link_actual_to_expense!(accrual.record_id, expense.record_id) } ],
        [ :eusa_actuals, "link_actual_to_budget!",
          -> { store.link_actual_to_budget!(accrual.record_id, budget.record_id) } ],
        [ :eusa_actuals, "link_offsetting_pair!",
          -> { store.link_offsetting_pair!(accrual.record_id, reversal.record_id) } ]
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

    # --- Budget updates ----------------------------------------------------

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

    # --- Financial-year scoping ---------------------------------------------

    def scoped_store(year) = DatabaseStore.new(financial_year: year)

    test "budgets_for_year lists only the store's year" do
      this_year = FinancialYear.create!(label: "Fringe 2027")
      last_year = FinancialYear.create!(label: "Fringe 2026", active: true)
      mine = Budget.create!(name: "Props", financial_year: this_year)
      Budget.create!(name: "Old props", financial_year: last_year)

      assert_equal [ mine.id ], scoped_store(this_year).budgets_for_year.map(&:id)
    end

    test "budgets_for_year returns every budget when the store has no year" do
      year = FinancialYear.create!(label: "Fringe 2027")
      Budget.create!(name: "Props", financial_year: year)
      Budget.create!(name: "Unstamped")

      # Jobs and the producer surfaces build an unscoped store; they must keep
      # seeing everything rather than silently losing the unstamped rows a
      # pre-financial-year database is full of.
      assert_equal 2, store.budgets_for_year.size
    end

    test "budgets stays unscoped so a name lookup resolves across years" do
      this_year = FinancialYear.create!(label: "Fringe 2027")
      last_year = FinancialYear.create!(label: "Fringe 2026", active: true)
      Budget.create!(name: "Props", financial_year: this_year)
      old = Budget.create!(name: "Old props", financial_year: last_year)

      # Review, the expenses index and every export resolve an expense's budget
      # name through this list. Scoping it would blank the name on last year's
      # claims while this year is selected.
      assert_includes scoped_store(this_year).budgets.map(&:id), old.id
    end

    test "budgets_with_actuals is scoped to the store's year" do
      this_year = FinancialYear.create!(label: "Fringe 2027")
      last_year = FinancialYear.create!(label: "Fringe 2026", active: true)
      mine = Budget.create!(name: "Props", financial_year: this_year)
      Budget.create!(name: "Old props", financial_year: last_year)

      assert_equal [ mine.id ], scoped_store(this_year).budgets_with_actuals.map(&:id)
    end

    test "active_budgets follows the ACTIVE year, not the selected one" do
      live = FinancialYear.create!(label: "Fringe 2026", active: true)
      draft = FinancialYear.create!(label: "Fringe 2027")
      live_budget = Budget.create!(name: "Props", active: true, financial_year: live)
      Budget.create!(name: "Next year props", active: true, financial_year: draft)

      # A finance user browsing next year's draft budgets must not be able to
      # file a claim against them — submitters file against the live year.
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

    test "budgets_for_year lists only the store's cost centre" do
      fringe = CostCentre.default
      termtime = second_cost_centre
      mine = Budget.create!(name: "Props", cost_centre: fringe)
      Budget.create!(name: "Termtime props", cost_centre: termtime)

      assert_equal [ mine.id ], centre_store(fringe).budgets_for_year.map(&:id)
    end

    test "a budget with no cost centre is in every centre's scope" do
      unplaced = Budget.create!(name: "Unplaced")

      # The same leniency as the financial-year scoping: a row written before
      # cost centres existed must not vanish from every screen at once.
      assert_includes centre_store(second_cost_centre).budgets_for_year.map(&:id), unplaced.id
    end

    test "budgets stays unscoped by cost centre so a name lookup still resolves" do
      termtime = second_cost_centre
      theirs = Budget.create!(name: "Termtime props", cost_centre: termtime)

      assert_includes centre_store(CostCentre.default).budgets.map(&:id), theirs.id
    end

    test "active_budgets is deliberately NOT cost-centre scoped" do
      termtime = second_cost_centre
      theirs = Budget.create!(name: "Termtime props", active: true, cost_centre: termtime)

      assert_includes centre_store(CostCentre.default).active_budgets.map(&:id), theirs.id
    end

    test "budgets_with_actuals is scoped to the store's cost centre" do
      fringe = CostCentre.default
      termtime = second_cost_centre
      mine = Budget.create!(name: "Props", cost_centre: fringe)
      Budget.create!(name: "Termtime props", cost_centre: termtime)

      assert_equal [ mine.id ], centre_store(fringe).budgets_with_actuals.map(&:id)
    end

    test "expenses_for_cost_centre resolves an expense's centre through its budget" do
      fringe = CostCentre.default
      termtime = second_cost_centre
      mine = Expense.create!(status: Status::PENDING,
                             budget: Budget.create!(name: "Props", cost_centre: fringe))
      Expense.create!(status: Status::PENDING,
                      budget: Budget.create!(name: "Termtime props", cost_centre: termtime))
      unplaced = Expense.create!(status: Status::PENDING)

      assert_equal [ mine.id, unplaced.id ].sort,
                   centre_store(fringe).expenses_for_cost_centre.map(&:id).sort
    end

    test "expenses stays unscoped by cost centre" do
      termtime = second_cost_centre
      theirs = Expense.create!(status: Status::PENDING,
                               budget: Budget.create!(name: "Termtime props", cost_centre: termtime))

      assert_includes centre_store(CostCentre.default).expenses.map(&:id), theirs.id
    end

    test "the money path owns an unplaced claim once, not once per centre" do
      fringe = CostCentre.default
      termtime = second_cost_centre
      unplaced = Expense.create!(status: Status::APPROVED)
      theirs = Expense.create!(status: Status::APPROVED,
                               budget: Budget.create!(name: "Termtime props", cost_centre: termtime))

      # The screens' filter shows it under both — that is safe, it pays nobody.
      assert_includes centre_store(fringe).expenses_for_cost_centre.map(&:id), unplaced.id
      assert_includes centre_store(termtime).expenses_for_cost_centre.map(&:id), unplaced.id

      # Build Batch must not: two centres selecting one claim can build it into
      # two BACS spreadsheets and two live EUSA drafts (limits_concurrency is
      # keyed per centre, so those builds do not serialise), and EUSA pays twice.
      assert_includes store.expenses_owned_by_cost_centre(fringe).map(&:id), unplaced.id
      assert_not_includes store.expenses_owned_by_cost_centre(termtime).map(&:id), unplaced.id
      assert_includes store.expenses_owned_by_cost_centre(termtime).map(&:id), theirs.id
    end

    test "the money path refuses to answer without a cost centre" do
      # "No cost centre" cannot mean "every centre" on a path that pays people,
      # and an empty answer would silently build an empty batch.
      assert_raises(ArgumentError) { store.expenses_owned_by_cost_centre(nil) }
    end

    test "eusa_actuals_for_cost_centre scopes on the row's own cost centre" do
      fringe = CostCentre.default
      termtime = second_cost_centre
      mine = EusaActual.create!(narrative: "Ours", debit: 10, cost_centre: fringe)
      EusaActual.create!(narrative: "Theirs", debit: 10, cost_centre: termtime)
      unplaced = EusaActual.create!(narrative: "Legacy", debit: 10)

      assert_equal [ mine.id, unplaced.id ].sort,
                   centre_store(fringe).eusa_actuals_for_cost_centre.map(&:id).sort
    end

    test "eusa_actuals stays unscoped so the reconcile dedup pool is whole" do
      termtime = second_cost_centre
      theirs = EusaActual.create!(narrative: "Theirs", debit: 10, cost_centre: termtime)

      assert_includes centre_store(CostCentre.default).eusa_actuals.map(&:id), theirs.id
    end

    test "unattributed_actuals is scoped to the store's cost centre" do
      fringe = CostCentre.default
      termtime = second_cost_centre
      mine = EusaActual.create!(narrative: "Ours", debit: 10, cost_centre: fringe)
      EusaActual.create!(narrative: "Theirs", debit: 10, cost_centre: termtime)

      assert_equal [ mine.id ], centre_store(fringe).unattributed_actuals.map(&:id)
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
      # Never re-homes a line another pot already owns, even if asked to.
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

    # The spreadsheet is the committee's route for revising a show's AGREED
    # TOTAL, and a revised Area Budget used to be silently dropped. It lands as
    # a forecast on the AREA, under the same update as the line revisions —
    # one committee meeting is one BudgetUpdate — and the area's own
    # initial_budget stays write-once, so Area#projected_amount moves while the
    # figure first agreed is still there to measure drift against.
    # #areas preloads every area-bound budget's expenses and forecasts — the
    # 10->36 shape Phase 1 guarded against — and a screen that only PRINTS a
    # name must not pay it.
    test "area_names_by_id costs one query however many budgets hang off the areas" do
      3.times do |n|
        area = Area.create!(name: "Area #{n}")
        3.times do |line|
          budget = Budget.create!(name: "Line #{line}", nominal_code: "4000", area: area)
          Expense.create!(budget: budget, description: "x", amount_excl_vat: 10)
          budget.forecasts.create!(amount: 20, date: Date.current)
        end
      end
      store = DatabaseStore.new

      assert_queries_count(1) { store.area_names_by_id }
      assert_equal 3, store.area_names_by_id.size
      assert_equal "Area 0", store.area_names_by_id[Area.order(:id).first.record_id]
    end

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

    test "import_budgets! creates the areas the sheet names before the budgets that reference them" do
      year = FinancialYear.create!(label: "Fringe 2027")
      cost_centre = CostCentre.default

      result = scoped_store(year).import_budgets!(
        creates: [ { name: "Cogito: Marketing", nominal_code: "4000", budget_type: "Expense",
                     active: true, financial_year: year, cost_centre: cost_centre,
                     owner_ids: [], area_name: "Cogito" } ],
        revisions: [], owner_syncs: [], note: "x", created_by: nil,
        area_creates: [ { name: "Cogito", cost_centre: cost_centre, financial_year: year } ]
      )

      area = Area.find_by(name: "Cogito")
      assert_not_nil area
      assert_equal area.id, Budget.find_by(name: "Cogito: Marketing").area_id
      assert_equal 1, result.areas_created
    end

    test "import_budgets! attaches a create to an area passed by id, creating none" do
      year = FinancialYear.create!(label: "Fringe 2027")
      cost_centre = CostCentre.default
      area = create_reimbursements_area(name: "Cogito", cost_centre: cost_centre, financial_year: year)

      result = scoped_store(year).import_budgets!(
        creates: [ { name: "Cogito: Marketing", nominal_code: "4000", budget_type: "Expense",
                     active: true, financial_year: year, cost_centre: cost_centre,
                     owner_ids: [], area_id: area.record_id } ],
        revisions: [], owner_syncs: [], note: "x", created_by: nil
      )

      assert_equal area.id, Budget.find_by(name: "Cogito: Marketing").area_id
      assert_equal 0, result.areas_created
      assert_equal 1, Area.where(name: "Cogito").count
    end

    # The re-home path shares #resolve_area with the creates, so a line moved
    # into an area this same import is creating resolves the same way — which
    # is what stops a re-import (every line matched, nothing created) leaving
    # the sheet's new area with no budget in it.
    test "import_budgets! moves a re-homed budget into an area the same import creates" do
      year = FinancialYear.create!(label: "Fringe 2027")
      cost_centre = CostCentre.default
      budget = Budget.create!(name: "Cogito: Marketing", financial_year: year,
                              cost_centre: cost_centre)

      result = scoped_store(year).import_budgets!(
        creates: [], revisions: [], owner_syncs: [], note: "x", created_by: nil,
        area_creates: [ { name: "Cogito", cost_centre: cost_centre, financial_year: year } ],
        re_homes: [ { budget_id: budget.record_id, area_name: "Cogito" } ]
      )

      assert_equal Area.find_by(name: "Cogito").id, budget.reload.area_id
      assert_equal 1, result.re_homed
    end

    test "import_budgets! moves a re-homed budget out of the area it was in" do
      year = FinancialYear.create!(label: "Fringe 2027")
      cost_centre = CostCentre.default
      improverts = create_reimbursements_area(name: "Improverts", cost_centre: cost_centre,
                                              financial_year: year)
      cogito = create_reimbursements_area(name: "Cogito", cost_centre: cost_centre,
                                          financial_year: year)
      budget = Budget.create!(name: "Cogito: Marketing", financial_year: year,
                              cost_centre: cost_centre, area: improverts)

      scoped_store(year).import_budgets!(
        creates: [], revisions: [], owner_syncs: [], note: "x", created_by: nil,
        re_homes: [ { budget_id: budget.record_id, area_id: cogito.record_id } ]
      )

      assert_equal cogito.id, budget.reload.area_id
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

    # --- Area owners: the sheet ADDS, and never removes -----------------------
    # A spreadsheet has no way to spell "remove this owner" — a blank cell says
    # nothing — and an owner dropped silently is a show's sign-off authority
    # gone. Removal stays hand-work on the area form.

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

    # The owner column is grouped by the area each line NAMES, ticked or not —
    # so an area every re-home into it was unticked out of never gets created,
    # and there is nothing to own.
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

    # THE property, not the branch: an empty list means "the sheet named
    # nobody", which must never read as "remove everyone".
    #
    # Its two defences are joint, and this goes red when BOTH are gone (checked):
    # the union makes the list a superset before `if union.any?` is ever
    # consulted, and the guard stops the bare list reaching Area#sync_owner_ids!
    # — a DIFF sync, whose `where.not(person_id: [])` is WHERE 1=1. Neither
    # alone reddens it, which is exactly why the guard is defence in depth and
    # not a reachable bug: see the method's own comment. There is deliberately
    # no test for the guarded branch by itself, because with the union in place
    # it can only be entered by an ownerless area asked to add nothing — a
    # no-op whose rows are scoped to that area either way, so no mutation of
    # this code can make such a test fail.
    test "add_area_owners! with an empty list removes nobody" do
      bob = Person.create!(name: "Bob", email: "bob@example.com")
      area = create_reimbursements_area(name: "Cogito")
      area.sync_owner_ids!([ bob.id ])

      store.add_area_owners!(area.record_id, [])

      assert_equal [ bob.record_id ], area.reload.owner_ids
    end

    # --- import_expenses! ----------------------------------------------------

    test "import_expenses! creates one claim per row, in one transaction" do
      pat = create_person
      budget = Budget.create!(name: "Props")

      created = store.import_expenses!(rows: [
        expense_row(pat, budget, key: "OLD-1"), expense_row(pat, budget, key: "OLD-2")
      ])

      assert_equal 2, created.size
      assert_equal %w[OLD-1 OLD-2], Expense.order(:id).pluck(:import_key)
    end

    test "import_expenses! writes nothing at all when one row fails" do
      pat = create_person
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

    # The sheet's own numbers are inserted BEFORE the rows that need one
    # assigned, or MAX+1 walks straight into a number the sheet is about to
    # claim — and create_expense! never retries past a number it was handed.
    test "import_expenses! honours the sheet's expense numbers without colliding" do
      pat = create_person
      budget = Budget.create!(name: "Props")

      store.import_expenses!(rows: [
        expense_row(pat, budget, key: "OLD-1"),
        expense_row(pat, budget, key: "OLD-2").merge(auto_number: 1)
      ])

      assert_equal [ 1, 2 ], Expense.order(:auto_number).pluck(:auto_number)
    end

    test "import_expenses! sends nothing and enqueues nothing" do
      pat = create_person
      budget = Budget.create!(name: "Props")

      assert_no_enqueued_jobs do
        assert_no_emails do
          store.import_expenses!(rows: [ expense_row(pat, budget, key: "OLD-1") ])
        end
      end
    end

    def expense_row(person, budget, key:)
      { person_record_id: person.record_id, budget_record_id: budget.record_id,
        status: Status::PAID, amount: BigDecimal("12.50"),
        amount_excl_vat: BigDecimal("12.50"), description: "Fake blood",
        payment_reference: "PROPS PAT", expense_type: Expense::TYPE_REIMBURSEMENT,
        payment_method: Expense::PAYMENT_METHOD_UK_BACS, import_key: key }
    end

    test "create_budget_update! stamps the store's year, not just the active one" do
      FinancialYear.create!(label: "Fringe 2026", active: true)
      draft = FinancialYear.create!(label: "Fringe 2027")
      budget = Budget.create!(name: "Props", financial_year: draft)

      update = scoped_store(draft).create_budget_update!(
        effective_date: Date.new(2027, 6, 1), note: "Committee budget", created_by: nil,
        forecasts: [ { budget_id: budget.record_id, amount: BigDecimal("500") } ]
      )

      assert_equal draft, update.financial_year
    end

    # --- settle_expense_from_actual! ----------------------------------------
    #
    # The one place a reconciled row settles its claim, shared by the reconcile
    # apply and the manual link on the Actuals index.

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

    # An international claim's stored amount was finance's GBP estimate, typed
    # at review because nobody knows the rate until the payment clears. Left
    # uncorrected, every budget rollup quotes the estimate forever.
    test "settling an international claim corrects its amount to what the bank charged" do
      expense, actual = settle_setup(international: true)

      store.settle_expense_from_actual!(actual.record_id, expense.record_id,
                                        payment_date: Date.new(2026, 5, 20),
                                        gbp_charged: BigDecimal("236.10"))

      settled = expense.reload
      assert_equal BigDecimal("236.10"), settled.amount
      assert_equal Status::PAID, settled.status
      assert_equal Date.new(2026, 5, 20), settled.payment_confirmed_date
    end

    # No reclaimable UK VAT on a foreign invoice, so Expense mirrors it.
    test "the corrected amount carries the ex-VAT figure with it" do
      expense, actual = settle_setup(international: true)

      store.settle_expense_from_actual!(actual.record_id, expense.record_id,
                                        payment_date: Date.new(2026, 5, 20),
                                        gbp_charged: BigDecimal("236.10"))

      assert_equal BigDecimal("236.10"), expense.reload.amount_excl_vat
    end

    # A UK claim's amount is what the producer actually spent, not an estimate.
    # Overwriting it from the ledger row would silently rewrite the claim to
    # whatever EUSA happened to book.
    test "settling a UK claim leaves its amount alone" do
      expense, actual = settle_setup(international: false)

      store.settle_expense_from_actual!(actual.record_id, expense.record_id,
                                        payment_date: Date.new(2026, 5, 20),
                                        gbp_charged: BigDecimal("236.10"))

      settled = expense.reload
      assert_equal BigDecimal("230.00"), settled.amount, "a UK amount is not an estimate"
      assert_equal Status::PAID, settled.status
    end

    test "settling links the actual to the expense" do
      expense, actual = settle_setup(international: true)

      store.settle_expense_from_actual!(actual.record_id, expense.record_id,
                                        payment_date: Date.new(2026, 5, 20),
                                        gbp_charged: BigDecimal("236.10"))

      assert_equal expense.id, actual.reload[:expense_id]
    end

    # --- Areas -----------------------------------------------------------

    test "areas is unscoped and areas_for_year is scoped to year and cost centre" do
      other = create_second_reimbursements_cost_centre
      mine = create_reimbursements_area(name: "Cogito", cost_centre: CostCentre.default)
      theirs = create_reimbursements_area(name: "Panto", cost_centre: other)

      store = DatabaseStore.new(
        financial_year: FinancialYear.current,
        cost_centre: CostCentre.default
      )

      assert_includes store.areas, theirs, "areas is an id->record lookup and must not be narrowed"
      assert_includes store.areas_for_year, mine
      assert_not_includes store.areas_for_year, theirs
    end

    test "areas_for_year returns every area when the store has no year or centre" do
      year = FinancialYear.create!(label: "Fringe 2027")
      create_reimbursements_area(name: "Cogito", financial_year: year)
      create_reimbursements_area(name: "Unstamped", financial_year: nil)

      assert_equal 2, store.areas_for_year.size
    end

    test "an area with no financial year or cost centre counts as belonging to every one" do
      unplaced = create_reimbursements_area(name: "Unplaced", financial_year: nil, cost_centre: nil)

      assert_includes scoped_store(FinancialYear.create!(label: "Fringe 2027")).areas_for_year.map(&:id),
                       unplaced.id
      assert_includes centre_store(second_cost_centre).areas_for_year.map(&:id), unplaced.id
    end

    test "find_area reads the row directly, unaffected by a stale memoized list" do
      store.areas # memoize empty
      area = create_reimbursements_area(name: "Cogito")

      assert_equal area.id, store.find_area(area.record_id).id
      assert_nil store.find_area("999999")
    end

    # The area edit page reads Area#committed_amount and #allocated, which call
    # the equivalent Budget readers per line — so without the same preload
    # #areas carries, the one screen those figures exist for pays two queries
    # per budget line.
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

    test "create_area! writes the permitted columns" do
      year = FinancialYear.create!(label: "Fringe 2027")
      cost_centre = CostCentre.default

      area = store.create_area!(name: "Cogito", initial_budget: BigDecimal("500"),
                                notes: "Autumn show", active: true,
                                cost_centre: cost_centre, financial_year: year)

      assert_equal "Cogito", area.name
      assert_equal BigDecimal("500"), area.initial_budget
      assert_equal "Autumn show", area.notes
      assert_equal cost_centre, area.cost_centre
      assert_equal year, area.financial_year
    end

    test "create_area! busts the memoized lists so a same-request relist sees it" do
      store.areas # memoize the empty list in
      store.areas_for_year # memoize the empty scoped list in

      created = store.create_area!(name: "Cogito")

      assert_includes store.areas.map(&:id), created.id
      assert_includes store.areas_for_year.map(&:id), created.id
    end

    test "update_area! updates the row and busts the memoized lists" do
      area = create_reimbursements_area(name: "Cogito")
      store.areas # memoize the stale name in

      updated = store.update_area!(area.record_id, name: "Cogito Renamed",
                                   initial_budget: BigDecimal("750"))

      assert_equal "Cogito Renamed", updated.name
      assert_equal BigDecimal("750"), updated.initial_budget
      assert_equal "Cogito Renamed", store.areas.find { |a| a.id == area.id }.name
    end

    test "sync_area_owners! diff-syncs the owners join table" do
      alice = Person.create!(name: "Alice", email: "alice@example.com")
      bob = Person.create!(name: "Bob", email: "bob@example.com")
      area = create_reimbursements_area(name: "Cogito")
      area.sync_owner_ids!([ alice.id ])
      store.areas # memoize the stale owner list in

      store.sync_area_owners!(area.record_id, [ bob.id ])

      assert_equal [ bob.record_id ], area.reload.owner_ids
      assert_equal [ bob.record_id ], store.areas.find { |a| a.id == area.id }.owner_ids
    end

    test "sync_area_owners! drops blank ids, the shape a multi-checkbox param takes" do
      alice = Person.create!(name: "Alice", email: "alice@example.com")
      area = create_reimbursements_area(name: "Cogito")

      # A Rails multi-checkbox posts a blank hidden default alongside any ticked
      # boxes. Area#sync_owner_ids! does person_ids.map(&:to_i) with no
      # filtering, so an unguarded blank becomes 0 and create!(person_id: 0)
      # raises ActiveRecord::InvalidForeignKey against reimbursements_area_owners.
      store.sync_area_owners!(area.record_id, [ "", alice.id.to_s ])

      assert_equal [ alice.record_id ], area.reload.owner_ids
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

      # Area#committed_amount and #allocated each call the equivalent Budget
      # reader per budget, which in turn reads the budget's expenses/forecasts
      # associations — without the preload an areas index N+1s once per budget
      # per area, per figure.
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
