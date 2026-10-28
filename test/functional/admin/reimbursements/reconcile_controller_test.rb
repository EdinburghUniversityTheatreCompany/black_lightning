require "test_helper"

module Admin
  module Reimbursements
  class ReconcileControllerTest < ActionController::TestCase
    include ReimbursementsTestHelpers

    # DatabaseStore whose actual-link writes raise for chosen targets.
    class FlakyLinkStore < ::Reimbursements::DatabaseStore
      attr_accessor :fail_expense_link_ids, :fail_budget_links

      def initialize(fail_expense_link_ids: [], fail_budget_links: false)
        super()
        @fail_expense_link_ids = fail_expense_link_ids
        @fail_budget_links = fail_budget_links
      end

      def link_actual_to_expense!(actual_id, expense_id)
        raise "blip" if fail_expense_link_ids.include?(expense_id.to_s)

        super
      end

      def link_actual_to_budget!(actual_id, budget_id)
        raise "blip" if fail_budget_links

        super
      end
    end

    # DatabaseStore that fails part-way through writing an offsetting pair: on the second leg's insert or the cross-link.
    class HalfPairStore < ::Reimbursements::DatabaseStore
      def initialize(fail_on:)
        super()
        @fail_on = fail_on
        @creates = 0
      end

      def create_actual!(attrs)
        @creates += 1
        raise "blip" if @fail_on == :second_leg && @creates == 2

        super
      end

      def link_offsetting_pair!(actual_id, counterpart_id)
        raise "blip" if @fail_on == :link

        super
      end
    end

    setup do
      @user = users(:member)
      grant_finance_permission(@user)

      # A Submitted expense the debit row matches: nominal 439999, 123.45 excl VAT, submitted within 14 days.
      @person = create_reimbursements_person(name: "Alice Producer", email: "alice@example.com")
      @budget = create_reimbursements_budget(name: "Props", nominal_code: "439999")
      @income = create_reimbursements_budget(name: "Ticket income", nominal_code: "250000",
                                             budget_type: "Income")
      @expense = create_reimbursements_expense(
        person: @person, budget: @budget, amount: BigDecimal("123.45"),
        amount_excl_vat: BigDecimal("123.45"), status: ::Reimbursements::Status::SUBMITTED,
        submitted_to_eusa_date: Date.new(2026, 5, 10), receipt: false
      )

      # Reconcile emails nobody: a real Notifier over a recording FakeGraphClient makes the no-email
      # test a genuine assertion, and a regression records here instead of reaching Graph.
      @graph = FakeGraphClient.new
      ReconcileController.notifier_builder =
        ->(cost_centre:) { ::Reimbursements::Notifier.new(cost_centre: cost_centre, graph: @graph) }
    end

    teardown do
      BaseController.store_builder = BaseController::DEFAULT_STORE_BUILDER
      ReconcileController.notifier_builder =
        ->(cost_centre:) { ::Reimbursements::Notifier.new(cost_centre: cost_centre) }
    end

    def debit_row(nominal: "439999", date: "13/05/2026", period: "03", narrative: "Alice Producer",
                  debit: "123.45", cost_centre: "F40")
      "#{nominal}\t#{cost_centre}\tBACS001\t#{date}\t#{period}\t#{narrative}\tShow\t#{debit}\t\t#{debit}"
    end

    def credit_row(nominal: "250000", date: "13/05/2026", period: "03", narrative: "Box office",
                   credit: "500.00", cost_centre: "F40")
      "#{nominal}\t#{cost_centre}\tBACS002\t#{date}\t#{period}\t#{narrative}\tTickets\t\t#{credit}\t-#{credit}"
    end

    def fringe_cost_centre
      ::Reimbursements::CostCentre.find_by!(eusa_code: "F40")
    end

    # --- Step 1: show ------------------------------------------------------

    test "show renders the paste form" do
      sign_in @user
      get :show

      assert_response :success
      assert_includes response.body, "Paste actuals data"
      assert_match(/emails its ledger export once a month/, response.body)
      assert_match(/ask them for the latest one/, response.body)
    end

    # --- Step 2: preview / parse + dedup + match ---------------------------

    # Saying so beats guessing a code, which would file another centre's ledger under this one.
    test "preview says so when no cost centre is configured, rather than assuming one" do
      sign_in @user
      ::Reimbursements::CostCentre.delete_all

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{debit_row}" }

      assert_response :success
      assert_includes response.body, "No cost centre is set up yet"
      assert_nil assigns(:matched_debits)
    end

    test "preview matches a debit row to a submitted expense" do
      sign_in @user
      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{debit_row}" }

      assert_response :success
      assert_equal 1, assigns(:matched_debits).size
      row, expense = assigns(:matched_debits).first
      assert_equal @expense.record_id, expense.record_id
      assert_equal BigDecimal("123.45"), row.debit
      assert_empty assigns(:unmatched_rows)
      # The operator is told what Apply does, and it does not include emailing.
      assert_match(/Nobody is emailed/, response.body)
      assert_no_match(/email those producers/, response.body)
      assert_includes response.body, edit_admin_reimbursements_expense_edit_path(@expense.record_id)
      assert_includes response.body, "Step 2"
      assert_includes response.body, "Step 3"
    end

    test "preview shows the gross amount of a claim matched on gross because its ex-VAT amount is 0" do
      @expense.update!(amount_excl_vat: BigDecimal("0"))
      sign_in @user

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{debit_row}" }

      assert_equal @expense.record_id, assigns(:matched_debits).sole.last.record_id
      assert_select "tbody tr td:last-child", text: "£123.45"
      assert_select "tbody tr td:last-child", text: "£0.00", count: 0
    end

    test "preview matches a credit row to an income budget" do
      sign_in @user
      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{credit_row}" }

      assert_response :success
      assert_equal 1, assigns(:matched_credits).size
      _row, budget = assigns(:matched_credits).first
      assert_equal @income.record_id, budget.record_id
    end

    test "the preview lists matched expenses, matched income and unmatched rows under their own columns" do
      sign_in @user
      paste = [ ACTUALS_HEADER, debit_row, credit_row,
                debit_row(nominal: "439000", narrative: "Stray debit", debit: "77.00"),
                credit_row(nominal: "251000", narrative: "Stray credit", credit: "9.99") ].join("\n")

      post :preview, params: { pasted_text: paste }

      assert_response :success
      tables = css_select("table").first(3)
      assert_equal [ [ "Nominal", "Period", "Date", "Narrative", "Debit", "Expense #", "Payee", "Expense amount" ],
                     %w[Nominal Period Date Narrative Credit Budget],
                     %w[Nominal Period Date Narrative Debit Credit Reason] ],
                   tables.map { |table| table.css("thead th").map { |th| th.text.squish } }
      expenses, income, unmatched = tables.map do |table|
        table.css("tbody tr").map { |tr| tr.css("td").map { |td| td.text.squish } }
      end
      assert_equal [ "439999", "03", "Alice Producer", "£123.45", "##{@expense.auto_number}", "Alice Producer", "£123.45" ],
                   expenses.sole.values_at(0, 1, 3, 4, 5, 6, 7)
      assert_equal [ "250000", "Box office", "£500.00", "Ticket income" ], income.sole.values_at(0, 3, 4, 5)
      assert_equal [ [ "439000", "Stray debit", "£77.00", "", "No matching Submitted or Paid claim" ],
                     [ "251000", "Stray credit", "", "£9.99", "No matching income budget" ] ],
                   unmatched.map { |cells| cells.values_at(0, 3, 4, 5, 6) }
    end

    test "a credit whose code two income budgets share is left for finance to place" do
      create_reimbursements_budget(name: "Sponsorship", nominal_code: "250000", budget_type: "Income")
      sign_in @user

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{credit_row}" }

      assert_empty assigns(:matched_credits)
      assert_equal 1, assigns(:unmatched_rows).size
      assert_select "td", text: /\A2 income budgets use this code/
    end

    test "apply saves a credit whose code two income budgets share without linking it" do
      create_reimbursements_budget(name: "Sponsorship", nominal_code: "250000", budget_type: "Income")
      sign_in @user

      post :apply, params: { pasted_text: "#{ACTUALS_HEADER}\n#{credit_row}" }

      assert_nil ::Reimbursements::EusaActual.sole.budget_id
      assert_equal 0, assigns(:credits_linked)
    end

    # An estimate pasted last month sits unplaced; this month's credit reverses it. Linking the
    # credit as income would count money that never arrived, so it waits for the ledger's pairing.
    def stored_estimate(**attrs)
      create_reimbursements_eusa_actual(nominal_code: "250000", debit: BigDecimal("500.00"),
                                        date: Date.new(2026, 4, 20), period: "01",
                                        cost_centre_id: fringe_cost_centre.id, **attrs)
    end

    test "a credit with an unplaced stored row of the opposite amount is held back, not linked" do
      stored_estimate
      sign_in @user

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{credit_row}" }

      assert_empty assigns(:matched_credits)
      assert_select "td", text: /\AA row of the opposite amount, on the ledger or in this paste/

      post :apply, params: { pasted_text: "#{ACTUALS_HEADER}\n#{credit_row}" }

      assert_nil ::Reimbursements::EusaActual.where.not(credit: nil).sole.budget_id
    end

    # Either credit may be the estimate's reversal, so neither is linked as income; the ledger
    # lists both possible pairs for a person.
    test "every pasted credit a stored row may reverse is held back, not just the first" do
      stored_estimate
      sign_in @user
      second = credit_row(narrative: "Box office again", date: "14/05/2026")

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{credit_row}\n#{second}" }

      assert_empty assigns(:matched_credits)
      assert_equal 2, assigns(:awaiting_reversal).size
    end

    # Too little evidence for the detector to pair them, but the debit may still be the credit's
    # partner, so the credit is not linked as income.
    # A third decimal is rounded away when stored; the hold-back judges the stored amount.
    test "a credit with a third decimal is judged at its stored amount" do
      stored_estimate
      sign_in @user

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{credit_row(credit: '500.004')}" }

      assert_empty assigns(:matched_credits)
      assert_equal 1, assigns(:awaiting_reversal).size
    end

    test "a pasted debit no claim takes holds back a credit of its amount in the same paste" do
      sign_in @user
      refund = debit_row(nominal: "250000", date: "20/09/2026", period: "06", narrative: "Refund",
                         debit: "500.00")

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{credit_row}\n#{refund}" }

      assert_empty assigns(:offsetting_pairs)
      assert_empty assigns(:matched_credits)
      assert_equal 1, assigns(:awaiting_reversal).size
    end

    test "a placed stored row, or one on another code, does not hold a credit back" do
      stored_estimate(nominal_code: "250001")
      stored_estimate(budget: @income)
      sign_in @user

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{credit_row}" }

      assert_equal 1, assigns(:matched_credits).size
    end

    # Only lines in the row's own cost centre compete for it.
    test "a credit still matches its centre's one income line when another centre's line shares the code" do
      termtime = create_second_reimbursements_cost_centre
      @income.update!(cost_centre: fringe_cost_centre)
      create_reimbursements_budget(name: "Ticket income", nominal_code: "250000", budget_type: "Income",
                                   cost_centre: termtime)
      sign_in @user

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{credit_row}" }

      assert_equal @income.record_id, assigns(:matched_credits).sole.last.record_id
    end

    # --- A credit competes only within its own financial year --------------
    #
    # Each year's show repeats its income line, code and all, so without the year two lines would
    # always tie and every credit would wait for a person to place it.

    def create_income_line(financial_year, nominal: "250000", name: "Ticket income")
      create_reimbursements_budget(name: name, nominal_code: nominal, budget_type: "Income",
                                   financial_year: financial_year)
    end

    test "a credit links to the income line of the year its date falls in" do
      this_year, next_year = create_reimbursements_tax_years
      @income.update!(financial_year: this_year)
      create_income_line(next_year)
      sign_in @user

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{credit_row}" }

      assert_equal @income.record_id, assigns(:matched_credits).sole.last.record_id
    end

    # Both years' lines are called "Ticket income", so the bare name cannot say which one it went to.
    test "the preview names the year of the income line a credit matched" do
      this_year, next_year = create_reimbursements_tax_years
      @income.update!(financial_year: this_year)
      create_income_line(next_year)
      sign_in @user

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{credit_row}" }

      assert_select "td", text: "Ticket income (2026/2027)"
    end

    test "the preview names a matched income line with no year bare" do
      sign_in @user

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{credit_row}" }

      assert_select "td", text: "Ticket income"
    end

    test "apply links a credit dated on a year's first day to that year's line" do
      this_year, next_year = create_reimbursements_tax_years
      @income.update!(financial_year: this_year)
      next_years_line = create_income_line(next_year)
      sign_in @user

      post :apply, params: { pasted_text: "#{ACTUALS_HEADER}\n#{credit_row(date: '06/04/2027', period: '01')}" }

      assert_equal next_years_line.id, ::Reimbursements::EusaActual.sole.budget_id
      assert_equal 1, assigns(:credits_linked)
    end

    test "apply files a row under the year its date falls in, not the active year" do
      last_year, _active = create_reimbursements_tax_years(active: "2027/2028")
      sign_in @user

      post :apply, params: { pasted_text: "#{ACTUALS_HEADER}\n#{debit_row(nominal: '500000', date: '20/03/2027')}" }

      assert_equal last_year, ::Reimbursements::EusaActual.sole.financial_year
    end

    # A line with no year counts in every year, so it still ties with the year's own line; the
    # other year's line is no longer among them.
    test "a credit stays unlinked when a line with no year shares its code with its year's line" do
      this_year, next_year = create_reimbursements_tax_years
      create_income_line(this_year, name: "Sponsorship")
      create_income_line(next_year)
      sign_in @user

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{credit_row}" }

      assert_empty assigns(:matched_credits)
      assert_select "td", text: /\A2 income budgets use this code/
    end

    test "a credit dated outside every year links on its code alone, as before years had dates" do
      this_year, _next_year = create_reimbursements_tax_years
      @income.update!(financial_year: this_year)
      sign_in @user

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{credit_row(date: '13/05/2025')}" }

      assert_equal @income.record_id, assigns(:matched_credits).sole.last.record_id
    end

    test "a credit dated outside every year still ties between two years' lines" do
      this_year, next_year = create_reimbursements_tax_years
      @income.update!(financial_year: this_year)
      create_income_line(next_year)
      sign_in @user

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{credit_row(date: '13/05/2025')}" }

      assert_empty assigns(:matched_credits)
      assert_select "td", text: /\A2 income budgets use this code/
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
      post :preview, params: { pasted_text: ACTUALS_HEADER }

      assert_response :success
      assert_includes response.body, "No data rows found"
    end

    test "apply redirects with an alert on a malformed paste" do
      sign_in @user
      bad_header = "Nominal\tCost Centre\tRef\tDate\tNarrative\tNarrative 1\tDebit\tCredit\tNet" # no Period
      post :apply, params: { pasted_text: "#{bad_header}\n#{debit_row}" }

      assert_redirected_to admin_reimbursements_reconciliation_path
      assert_match(/Could not parse the actuals/, flash[:alert])
      assert_equal 0, ::Reimbursements::EusaActual.count
    end

    test "an expense with a payment_confirmed_date but no linked actual is excluded from matching" do
      @expense.update!(payment_confirmed_date: Date.new(2026, 5, 1))
      sign_in @user

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{debit_row}" }

      assert_response :success
      assert_empty assigns(:matched_debits), "already-paid-by-another-route expenses must not be re-matched"
      assert_equal 1, assigns(:unmatched_rows).size
    end

    test "a single paste dedups each period independently" do
      create_reimbursements_actual(nominal_code: "439999", period: "03",
                                   narrative: "Alice Producer", debit: BigDecimal("123.45"))
      sign_in @user

      two_rows = "#{ACTUALS_HEADER}\n#{debit_row(period: '03')}\n#{debit_row(period: '04')}"
      post :preview, params: { pasted_text: two_rows }

      assert_response :success
      assert_equal 1, assigns(:skipped_rows).size
      assert_equal "03", assigns(:skipped_rows).first.period
      assert_equal 1, assigns(:new_rows).size
      assert_equal "04", assigns(:new_rows).first.period
    end

    test "one expense is claimed by at most one debit row" do
      sign_in @user
      two_rows = "#{ACTUALS_HEADER}\n#{debit_row}\n#{debit_row(date: '14/05/2026')}"
      post :preview, params: { pasted_text: two_rows }

      assert_response :success
      assert_equal 1, assigns(:matched_debits).size
      assert_equal 1, assigns(:unmatched_rows).size, "the second row can't reclaim the same expense"
    end

    # --- Step 3: apply -----------------------------------------------------

    test "apply creates actuals, links them, and flips the expense to Paid without emailing" do
      sign_in @user

      post :apply, params: { pasted_text: "#{ACTUALS_HEADER}\n#{debit_row}" }

      assert_empty @graph.send_mails, "marking an expense Paid must not email the producer"
      assert_match(/Nobody was emailed/, response.body, "and the apply page says so")

      assert_response :success
      actual = ::Reimbursements::EusaActual.sole
      assert_equal @expense.id, actual.expense_id
      @expense.reload
      assert_equal ::Reimbursements::Status::PAID, @expense.status
      assert_equal Date.new(2026, 5, 13), @expense.payment_confirmed_date
      assert_equal 1, assigns(:expenses_paid)
      assert_not_includes response.body, "on the EUSA Actuals ledger"
    end

    test "apply links a matched credit to its budget" do
      sign_in @user

      post :apply, params: { pasted_text: "#{ACTUALS_HEADER}\n#{credit_row}" }

      assert_response :success
      assert_equal @income.id, ::Reimbursements::EusaActual.sole.budget_id
      assert_equal 1, assigns(:credits_linked)
    end

    test "apply saves an unmatched row, pays nothing, and links to the needs-attention ledger" do
      sign_in @user

      post :apply, params: {
        pasted_text: "#{ACTUALS_HEADER}\n#{debit_row(nominal: '999999')}"
      }

      assert_response :success
      assert_equal 1, assigns(:unmatched_saved)
      assert_equal 0, assigns(:expenses_paid)
      assert_equal ::Reimbursements::Status::SUBMITTED, @expense.reload.status
      assert_includes response.body, "on the EUSA Actuals ledger"
      assert_includes response.body, admin_reimbursements_actuals_path(state: "needs_attention")
      # A link out of the wizard's Turbo Frame needs "_top", or Turbo renders "Content missing".
      assert_select "a[data-turbo-frame='_top']"
    end

    # --- Possible matches: the amount differs, the narrative names the claim --

    def probable_key(text, expense)
      row = ::Reimbursements::Reconciliation.parse_actuals_rows("#{ACTUALS_HEADER}\n#{text}").sole
      ::Reimbursements::Reconciliation::ProbableMatch.new(row: row, expense: expense, reasons: []).key
    end

    test "preview offers a debit of another amount for the claim it names, unticked, with the difference" do
      sign_in @user
      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{debit_row(debit: '118.45')}" }

      assert_response :success
      assert_empty assigns(:matched_debits)
      assert_empty assigns(:unmatched_rows), "a possible match is listed once, not also as unmatched"
      match = assigns(:probable_matches).sole
      assert_equal @expense.record_id, match.expense.record_id
      assert_select "input[type=checkbox][name='probable_match_keys[]'][value=?]", match.key
      assert_select "input[type=checkbox][name='probable_match_keys[]'][checked]", count: 0
      assert_includes response.body, "£5.00 less"
    end

    test "preview says when EUSA paid the claim's total including VAT" do
      @expense.update!(amount: BigDecimal("148.14"))
      sign_in @user
      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{debit_row(debit: '148.14')}" }

      assert_equal @expense.record_id, assigns(:probable_matches).sole.expense.record_id
      assert_select "td", text: "EUSA paid the total including VAT, so ticking it counts the VAT as spent"
    end

    test "apply of a ticked match at the total including VAT counts the VAT as spent" do
      @expense.update!(amount: BigDecimal("148.14"))
      row = debit_row(debit: "148.14")
      sign_in @user

      post :apply, params: { pasted_text: "#{ACTUALS_HEADER}\n#{row}",
                             probable_match_keys: [ "", probable_key(row, @expense) ] }

      assert_equal BigDecimal("148.14"), @expense.reload.amount_excl_vat
    end

    test "apply settles a ticked possible match and keeps the amount the producer claimed" do
      row = debit_row(debit: "118.45")
      sign_in @user

      post :apply, params: { pasted_text: "#{ACTUALS_HEADER}\n#{row}",
                             probable_match_keys: [ "", probable_key(row, @expense) ] }

      assert_response :success
      assert_equal @expense.id, ::Reimbursements::EusaActual.sole.expense_id
      @expense.reload
      assert_equal ::Reimbursements::Status::PAID, @expense.status
      assert_equal BigDecimal("123.45"), @expense.amount, "a UK claim keeps what the producer spent"
      assert_equal 1, assigns(:expenses_paid)
      assert_equal 0, assigns(:unmatched_saved)
    end

    test "apply imports an unticked possible match unmatched and pays nothing" do
      sign_in @user

      post :apply, params: { pasted_text: "#{ACTUALS_HEADER}\n#{debit_row(debit: '118.45')}",
                             probable_match_keys: [ "" ] }

      assert_nil ::Reimbursements::EusaActual.sole.expense_id
      assert_equal ::Reimbursements::Status::SUBMITTED, @expense.reload.status
      assert_equal 1, assigns(:unmatched_saved)
    end

    # The key carries the claim: a tick made against one claim never settles another.
    test "apply ignores a ticked key whose claim the re-parse no longer offers" do
      row = debit_row(debit: "118.45")
      other = create_reimbursements_expense(person: @person, budget: @budget,
                                            status: ::Reimbursements::Status::SUBMITTED, receipt: false)
      sign_in @user

      post :apply, params: { pasted_text: "#{ACTUALS_HEADER}\n#{row}",
                             probable_match_keys: [ "", probable_key(row, other) ] }

      assert_nil ::Reimbursements::EusaActual.sole.expense_id
      assert_equal ::Reimbursements::Status::SUBMITTED, other.reload.status
    end

    test "a claim two rows point at is offered for neither" do
      sign_in @user
      rows = [ debit_row(debit: "118.45"), debit_row(debit: "110.00") ].join("\n")

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{rows}" }

      assert_empty assigns(:probable_matches)
      assert_equal 2, assigns(:unmatched_rows).size
    end

    # --- Groups: one row paying several claims, several rows paying one ------

    def alice_claim(amount)
      create_reimbursements_expense(person: @person, budget: @budget, amount: BigDecimal(amount),
                                    amount_excl_vat: BigDecimal(amount), status: ::Reimbursements::Status::SUBMITTED,
                                    submitted_to_eusa_date: Date.new(2026, 5, 10), receipt: false)
    end

    def group_key(texts, expenses)
      rows = ::Reimbursements::Reconciliation.parse_actuals_rows("#{ACTUALS_HEADER}\n#{texts.join("\n")}")
      ::Reimbursements::Reconciliation::GroupMatch.new(rows: rows, expenses: expenses).key
    end

    test "preview offers one row as paying the group of claims it adds up to, unticked" do
      first = alice_claim("30.00")
      second = alice_claim("12.00")
      sign_in @user

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{debit_row(debit: '42.00')}" }

      group = assigns(:group_matches).sole
      assert_equal [ first.record_id, second.record_id ].sort, group.expenses.map(&:record_id).sort
      assert_empty assigns(:unmatched_rows)
      assert_select "input[type=checkbox][value=?]:not([checked])", group.key
      assert_select "td", text: "one payment for 2 claims"
    end

    test "apply shares a ticked row across its claims; an unticked one is imported unmatched" do
      first = alice_claim("30.00")
      second = alice_claim("12.00")
      text = debit_row(debit: "42.00")
      sign_in @user

      post :apply, params: { pasted_text: "#{ACTUALS_HEADER}\n#{text}",
                             probable_match_keys: [ "", group_key([ text ], [ first, second ]) ] }

      actual = ::Reimbursements::EusaActual.sole
      assert_equal [ BigDecimal("12"), BigDecimal("30") ], actual.claim_shares.pluck(:amount).sort
      assert_equal ::Reimbursements::Status::PAID, first.reload.status
      assert_equal 2, assigns(:expenses_paid)
    end

    test "apply settles a claim from the ticked rows that pay it in parts" do
      claim = alice_claim("76.18")
      texts = [ debit_row(debit: "14.98"), debit_row(debit: "61.19") ]
      sign_in @user

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{texts.join("\n")}" }
      assert_equal [ claim.record_id ], assigns(:group_matches).sole.expenses.map(&:record_id)

      post :apply, params: { pasted_text: "#{ACTUALS_HEADER}\n#{texts.join("\n")}",
                             probable_match_keys: [ "", group_key(texts, [ claim ]) ] }

      assert_equal [ claim.id ] * 2, ::Reimbursements::EusaActual.pluck(:expense_id)
      assert_equal ::Reimbursements::Status::PAID, claim.reload.status
    end

    # --- Claims the claims import brought in as Paid ------------------------
    #
    # They carry no sent-to-EUSA or payment date, only when they were submitted, and a committee
    # running claims outside the portal often has budgets with no nominal code.

    def imported_claim(budget: @budget)
      create_reimbursements_expense(person: @person, budget: budget, amount: BigDecimal("123.45"),
                                    amount_excl_vat: BigDecimal("123.45"), status: ::Reimbursements::Status::PAID,
                                    submitted_at: Time.zone.local(2026, 5, 12, 10), import_key: "OLD-1",
                                    receipt: false)
    end

    test "apply settles an imported Paid claim by the date it was submitted" do
      @expense.update!(status: ::Reimbursements::Status::REJECTED)
      claim = imported_claim
      sign_in @user

      post :apply, params: { pasted_text: "#{ACTUALS_HEADER}\n#{debit_row}" }

      assert_equal claim.id, ::Reimbursements::EusaActual.sole.expense_id
      assert_equal Date.new(2026, 5, 13), claim.reload.payment_confirmed_date
    end

    test "a claim whose budget has no nominal code is offered, never matched, and says why" do
      @expense.update!(status: ::Reimbursements::Status::REJECTED)
      claim = imported_claim(budget: create_reimbursements_budget(name: "Theatre", nominal_code: ""))
      sign_in @user

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{debit_row}" }

      assert_empty assigns(:matched_debits)
      assert_equal claim.record_id, assigns(:probable_matches).sole.expense.record_id
      assert_select "td", text: "same amount as claimed; its budget has no nominal code"
    end

    test "a claim another row matched exactly is not offered again" do
      sign_in @user
      rows = [ debit_row, debit_row(debit: "110.00") ].join("\n")

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{rows}" }

      assert_equal 1, assigns(:matched_debits).size
      assert_empty assigns(:probable_matches)
    end

    test "an already-reconciled expense is not re-matched by a later paste" do
      # @expense was paid in an earlier period and linked to an actual. A later export carries a
      # near-identical row (different narrative) that dedup does not skip; the re-pay guard must.
      @expense.update!(status: ::Reimbursements::Status::PAID)
      create_reimbursements_actual(nominal_code: "439999", period: "02",
                                   narrative: "Alice Producer OLD",
                                   debit: BigDecimal("123.45"), expense: @expense)
      sign_in @user

      post :apply, params: {
        pasted_text: "#{ACTUALS_HEADER}\n#{debit_row(narrative: 'Alice Producer NEW')}"
      }

      assert_response :success
      assert_equal 0, assigns(:expenses_paid)
      assert_equal 1, assigns(:unmatched_saved)
      assert_nil @expense.reload.payment_confirmed_date
    end

    test "a mid-batch row failure doesn't abort the rest, and is surfaced instead of hidden" do
      second_expense = create_reimbursements_expense(
        person: @person, budget: @budget, amount: BigDecimal("55.00"),
        amount_excl_vat: BigDecimal("55.00"), status: ::Reimbursements::Status::SUBMITTED,
        submitted_to_eusa_date: Date.new(2026, 5, 10), nominal_code_override: "555555",
        receipt: false
      )
      # second_expense's link write fails after its Actual was created; @expense's row is untouched.
      BaseController.store_builder = ->(**) { FlakyLinkStore.new(fail_expense_link_ids: [ second_expense.record_id ]) }
      sign_in @user

      post :apply, params: {
        pasted_text: "#{ACTUALS_HEADER}\n#{debit_row}\n#{debit_row(nominal: '555555', narrative: 'Alice Producer', debit: '55.00')}"
      }

      assert_response :success
      assert_equal 1, assigns(:expenses_paid)
      assert_equal ::Reimbursements::Status::PAID, @expense.reload.status
      assert_equal ::Reimbursements::Status::SUBMITTED, second_expense.reload.status
      assert_match(/expense #.*blip/i, assigns(:reconciliation_errors).sole)
      assert_match(/hit a problem/i, response.body)
    end

    test "a failed credit row is not counted in credits_linked" do
      BaseController.store_builder = ->(**) { FlakyLinkStore.new(fail_budget_links: true) }
      sign_in @user

      post :apply, params: { pasted_text: "#{ACTUALS_HEADER}\n#{credit_row}" }

      assert_response :success
      assert_equal 0, assigns(:credits_linked), "a row whose link write failed must not count as linked"
      assert_match(/budget Ticket income.*blip/i, assigns(:reconciliation_errors).sole)
    end

    test "apply redirects when the pasted text is missing" do
      sign_in @user
      post :apply, params: { pasted_text: "" }

      assert_redirected_to admin_reimbursements_reconciliation_path
    end

    # --- Offsetting pairs --------------------------------------------------
    #
    # An accrual and its reversal on one nominal code and reference, a day apart in consecutive
    # periods: the shape that dominates a real EUSA export.

    ACCRUAL_REF = "J000000884".freeze
    ACCRUAL_NOMINAL = "331300".freeze

    def accrual_row(nominal: ACCRUAL_NOMINAL, ref: ACCRUAL_REF, date: "27/04/2026", period: "01",
                    narrative: "Venue hire accrual", amount: "500.00", cost_centre: "F40")
      "#{nominal}\t#{cost_centre}\t#{ref}\t#{date}\t#{period}\t#{narrative}\tShow\t#{amount}\t\t#{amount}"
    end

    def reversal_row(nominal: ACCRUAL_NOMINAL, ref: ACCRUAL_REF, date: "28/04/2026", period: "02",
                     narrative: "Venue hire accrual", amount: "500.00", cost_centre: "F40")
      "#{nominal}\t#{cost_centre}\t#{ref}\t#{date}\t#{period}\t#{narrative}\tShow\t\t#{amount}\t-#{amount}"
    end

    def offsetting_paste
      "#{ACTUALS_HEADER}\n#{accrual_row}\n#{reversal_row}"
    end

    def lookalike_expense
      create_reimbursements_expense(
        person: @person, budget: @budget, amount: BigDecimal("500.00"),
        amount_excl_vat: BigDecimal("500.00"), status: ::Reimbursements::Status::SUBMITTED,
        submitted_to_eusa_date: Date.new(2026, 4, 27), nominal_code_override: ACCRUAL_NOMINAL,
        receipt: false
      )
    end

    test "preview proposes an offsetting pair instead of listing both legs as unmatched" do
      sign_in @user
      post :preview, params: { pasted_text: offsetting_paste }

      assert_response :success
      pair = assigns(:offsetting_pairs).sole
      assert_equal BigDecimal("500.00"), pair.debit_row.debit
      assert_equal BigDecimal("500.00"), pair.credit_row.credit
      assert_empty assigns(:unmatched_rows), "a paired row is not an unmatched row"
      assert_select "input[type=checkbox][name='offset_pair_keys[]'][value=?][checked=checked]", pair.key
      assert_nil assigns(:offset_pair_consequences)[pair.key][:expense]
      assert_no_match(/if you untick/i, response.body)
    end

    # The point of pairing: an accrual leg that looks like a real claim must not pay it. Only rows
    # left OUT of a pair reach the debit-to-expense matcher.
    test "apply writes a ticked pair as two cross-linked offset legs that pay nothing" do
      lookalike = lookalike_expense
      sign_in @user

      post :apply, params: { pasted_text: offsetting_paste, offset_pair_keys: offsetting_pair_keys(offsetting_paste) }

      legs = ::Reimbursements::EusaActual.order(:id).to_a
      assert_equal 2, legs.size, "both legs are kept for the audit trail"
      assert legs.all?(&:offset?)
      assert_equal [ legs.last.id, legs.first.id ], legs.map(&:offset_of_id)
      assert_equal [ 1, 0, 0 ], assigns.values_at("offsets_linked", "unmatched_saved", "expenses_paid")
      assert_equal ::Reimbursements::Status::SUBMITTED, lookalike.reload.status
    end

    # Unticking hands the legs back to the ordinary matcher, so a leg that matches pays: the
    # operator's judgement, not the heuristic's.
    test "an unticked pair's legs import as ordinary rows and go back to the matcher" do
      lookalike = lookalike_expense
      sign_in @user

      post :apply, params: { pasted_text: offsetting_paste, offset_pair_keys: [ "" ] }

      assert_equal 2, ::Reimbursements::EusaActual.count
      assert ::Reimbursements::EusaActual.none?(&:offset?)
      assert_equal [ 0, 1, 1 ], assigns.values_at("offsets_linked", "expenses_paid", "unmatched_saved")
      assert_equal ::Reimbursements::Status::PAID, lookalike.reload.status
    end

    # Unticking says the two legs are not each other's reversal, so the credit is linked as income.
    test "an unticked pair's credit is not held back by its own debit" do
      income = create_reimbursements_budget(name: "Venue hire", nominal_code: ACCRUAL_NOMINAL,
                                            budget_type: "Income")
      sign_in @user

      post :apply, params: { pasted_text: offsetting_paste, offset_pair_keys: [ "" ] }

      assert_equal income.id, ::Reimbursements::EusaActual.where("credit > 0").sole.budget_id
    end

    # Unticking frees the credit from that one debit only; another credit it may reverse still waits.
    test "an unticked pair's debit still holds back another credit of its amount" do
      income = create_reimbursements_budget(name: "Venue hire", nominal_code: ACCRUAL_NOMINAL,
                                            budget_type: "Income")
      other = reversal_row(ref: "SI0099", date: "15/06/2026", period: "03", narrative: "Hire takings")
      sign_in @user

      post :preview, params: { pasted_text: "#{offsetting_paste}\n#{other}" }

      assert_equal "Venue hire accrual", assigns(:offsetting_pairs).sole.credit_row.narrative

      post :apply, params: { pasted_text: "#{offsetting_paste}\n#{other}", offset_pair_keys: [ "" ] }

      credits = ::Reimbursements::EusaActual.where("credit > 0").index_by(&:narrative)
      assert_equal income.id, credits["Venue hire accrual"].budget_id
      assert_nil credits["Hire takings"].budget_id
    end

    test "a same-amount row that is not part of a pair still reaches the matcher" do
      sign_in @user
      paste = "#{offsetting_paste}\n#{debit_row}"

      post :preview, params: { pasted_text: paste }

      assert_response :success
      assert_equal 1, assigns(:offsetting_pairs).size
      assert_equal @expense.record_id, assigns(:matched_debits).sole.last.record_id
    end

    # --- The preview is honest about what unticking would do ---------------
    #
    # The matched-expenses count covers UNPAIRED rows only, but apply hands an unticked pair's legs
    # back to the matcher, so each pair states what unticking it would pay.

    test "the preview spells out the expense a pair would pay if unticked" do
      lookalike = lookalike_expense
      sign_in @user

      post :preview, params: { pasted_text: offsetting_paste }

      assert_response :success
      assert_empty assigns(:matched_debits), "a paired row is not in the ordinary matching"
      key = assigns(:offsetting_pairs).sole.key
      assert_equal lookalike.record_id, assigns(:offset_pair_consequences)[key][:expense].record_id
      assert_select "td[colspan=7]", text: /If you untick this pair.*##{lookalike.auto_number}/m
      assert_select "td[rowspan=3]", 2, "the checkbox and score cells span the note row"
      assert_includes response.body, "can add to that count"
    end

    test "the preview names the income line of the credit leg's own year if a pair is unticked" do
      this_year, next_year = create_reimbursements_tax_years
      this_years_line = create_income_line(this_year, nominal: ACCRUAL_NOMINAL, name: "Venue hire income")
      create_income_line(next_year, nominal: ACCRUAL_NOMINAL, name: "Venue hire income")
      sign_in @user

      post :preview, params: { pasted_text: offsetting_paste }

      key = assigns(:offsetting_pairs).sole.key
      assert_equal this_years_line.record_id, assigns(:offset_pair_consequences)[key][:budget].record_id
      assert_select "td[colspan=7] strong", text: "Venue hire income (2026/2027)"
    end

    # Two pairs that both look like the same expense must not both claim it:
    # apply matches each expense once, so the preview has to as well.
    test "two identical pairs never both claim the same expense if unticked" do
      lookalike_expense
      sign_in @user

      post :preview, params: { pasted_text: [ ACTUALS_HEADER, accrual_row, reversal_row,
                                              accrual_row, reversal_row ].join("\n") }

      assert_response :success
      claimed = assigns(:offset_pair_consequences).values.filter_map { |c| c[:expense] }
      assert_equal 1, claimed.size, "the second pair has no expense left to pay"
    end

    # --- A pair is written all-or-nothing ----------------------------------
    #
    # A half-written pair leaves the debit leg unstamped, so every rollup reads it as real spend, and
    # re-pasting cannot repair it because dedup then skips that leg.

    %i[second_leg link].each do |fail_on|
      test "a pair whose #{fail_on.to_s.tr('_', ' ')} write fails writes neither leg" do
        BaseController.store_builder = ->(**) { HalfPairStore.new(fail_on: fail_on) }
        sign_in @user

        post :apply, params: { pasted_text: offsetting_paste, offset_pair_keys: offsetting_pair_keys(offsetting_paste) }

        assert_equal 0, ::Reimbursements::EusaActual.count, "a stranded leg would read as real spend forever"
        assert_equal 0, assigns(:offsets_linked)
        assert_match(/offsetting pair.*blip/i, assigns(:reconciliation_errors).sole)
      end
    end

    # --- Duplicate pairs ---------------------------------------------------
    #
    # A paste can hold the same accrual and reversal twice: two pairs, which need two tickboxes so
    # that ticking one and unticking the other means exactly that.

    def duplicate_pairs_paste
      accrual = accrual_row(amount: "10.00")
      reversal = reversal_row(amount: "10.00")
      [ ACTUALS_HEADER, accrual, reversal, accrual, reversal ].join("\n")
    end

    test "two byte-identical pairs render as two separately tickable rows" do
      sign_in @user
      post :preview, params: { pasted_text: duplicate_pairs_paste }

      assert_response :success
      pairs = assigns(:offsetting_pairs)
      assert_equal 2, pairs.size
      assert_equal 2, pairs.map(&:key).uniq.size, "two real pairs, two keys"
      pairs.each do |pair|
        assert_select "input[type=checkbox][name='offset_pair_keys[]'][value=?][checked=checked]",
                      pair.key
        assert_select "##{"offset-pair-#{pair.key}"}", 1, "each checkbox needs its own DOM id"
      end
    end

    test "unticking one of two identical pairs offsets only the other" do
      sign_in @user
      keys = offsetting_pair_keys(duplicate_pairs_paste)
      assert_equal 2, keys.uniq.size, "the two pairs must be distinguishable to begin with"

      post :apply, params: { pasted_text: duplicate_pairs_paste, offset_pair_keys: [ keys.first ] }

      assert_response :success
      assert_equal 1, assigns(:offsets_linked)
      assert_equal 4, ::Reimbursements::EusaActual.count, "all four rows are still imported"
      assert_equal 2, ::Reimbursements::EusaActual.all.count(&:offset?),
                   "only the ticked pair's two legs are stamped offset"
      assert_equal 2, assigns(:unmatched_saved),
                   "the unticked pair's legs are imported as ordinary rows"
    end

    # --- Per-row cost centres ----------------------------------------------

    test "a paste spanning two cost centres imports every row under its own" do
      create_second_reimbursements_cost_centre
      sign_in @user
      paste = [ ACTUALS_HEADER, debit_row(narrative: "Fringe spend"),
                debit_row(narrative: "Termtime spend", cost_centre: "BED") ].join("\n")

      post :apply, params: { pasted_text: paste }

      assert_response :success
      actuals = ::Reimbursements::EusaActual.order(:id).to_a
      assert_equal %w[F40 BED], actuals.map { |actual| actual.cost_centre.eusa_code },
                   "each row resolves through the association to the pot its own code named"
    end

    # Another society's spend in a whole-organisation export: skipped, but never silently.
    test "preview reports the rows it skipped for an unconfigured cost centre, and names the codes" do
      sign_in @user
      paste = [ ACTUALS_HEADER, debit_row, debit_row(narrative: "Someone else", cost_centre: "G12"),
                debit_row(narrative: "Someone else again", cost_centre: "H03") ].join("\n")

      post :preview, params: { pasted_text: paste }

      assert_response :success
      assert_equal 2, assigns(:attribution).unrecognised_rows.size
      assert_equal %w[G12 H03], assigns(:attribution).unrecognised_codes
      assert_match(/2 rows skipped/, response.body)
      assert_match(/G12 and H03/, response.body)
    end

    test "apply imports only the rows whose cost centre is set up here" do
      sign_in @user
      paste = [ ACTUALS_HEADER, debit_row, debit_row(narrative: "Someone else", cost_centre: "G12") ].join("\n")

      post :apply, params: { pasted_text: paste }

      assert_response :success
      assert_equal [ fringe_cost_centre.id ], ::Reimbursements::EusaActual.pluck(:cost_centre_id)
      assert_match(/not set up here/, response.body)
    end

    # --- Blank cost centres always need an explicit answer -----------------

    def blank_centre_paste
      [ ACTUALS_HEADER, debit_row, debit_row(narrative: "No centre named", cost_centre: "") ].join("\n")
    end

    # Not inferred even here, with the fixture as the only centre: that guess files real spend under
    # the wrong pot once a second exists.
    test "preview asks where blank-cost-centre rows belong rather than assuming the only centre" do
      sign_in @user

      post :preview, params: { pasted_text: blank_centre_paste }

      assert_response :success
      assert assigns(:attribution).blank_choice_required?
      assert_select "select[name=blank_cost_centre_id]"
      assert_select "option[value=?]", fringe_cost_centre.id.to_s
      assert_select "option[value=skip]"
      assert_select "input[type=submit][value='Apply reconciliation']", false,
                    "nothing may be applied while the question is unanswered"
    end

    test "apply refuses the whole paste while blank rows have no cost centre" do
      sign_in @user

      post :apply, params: { pasted_text: blank_centre_paste }

      assert_response :success
      assert_equal 0, ::Reimbursements::EusaActual.count,
                   "importing the attributed rows and losing the rest is the silent drop this prevents"
      assert_equal ::Reimbursements::Status::SUBMITTED, @expense.reload.status
      assert_match(/no cost centre of their own/, response.body)
    end

    test "a chosen cost centre imports the blank rows under it" do
      termtime = create_second_reimbursements_cost_centre
      sign_in @user

      post :apply, params: { pasted_text: blank_centre_paste, blank_cost_centre_id: termtime.id.to_s }

      assert_response :success
      actuals = ::Reimbursements::EusaActual.order(:id).to_a
      assert_equal 2, actuals.size
      assert_equal [ fringe_cost_centre.id, termtime.id ], actuals.map(&:cost_centre_id),
                   "the blank row lands in the pot the operator named, not the one its neighbour used"
    end

    test "the skip choice imports the rest and drops the blank rows" do
      sign_in @user

      post :apply, params: { pasted_text: blank_centre_paste,
                             blank_cost_centre_id: ::Reimbursements::ActualsAttribution::SKIP }

      assert_response :success
      assert_equal [ fringe_cost_centre.id ], ::Reimbursements::EusaActual.pluck(:cost_centre_id)
      assert_match(/skipped, as you chose/, response.body)
    end

    # --- Offsetting pairs never span cost centres --------------------------
    #
    # A false positive hides real spend from BOTH pots' rollups; a false negative leaves two visible rows.

    test "an accrual and a reversal in different cost centres are never paired" do
      create_second_reimbursements_cost_centre
      sign_in @user
      paste = [ ACTUALS_HEADER, accrual_row, reversal_row(cost_centre: "BED") ].join("\n")

      post :preview, params: { pasted_text: paste }

      assert_response :success
      assert_empty assigns(:offsetting_pairs)
      assert_equal 2, assigns(:unmatched_rows).size
    end

    # --- Matching is scoped to the row's cost centre -----------------------

    test "rows never match an expense or income budget in another cost centre" do
      termtime = create_second_reimbursements_cost_centre
      @budget.update!(cost_centre: termtime)
      @income.update!(cost_centre: termtime)
      sign_in @user

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{debit_row}\n#{credit_row}" }

      assert_empty assigns(:matched_debits), "a Fringe debit must not pay a termtime claim"
      assert_empty assigns(:matched_credits)
      assert_equal 2, assigns(:unmatched_rows).size
    end

    test "a debit row matches an expense whose budget is in its own cost centre" do
      create_second_reimbursements_cost_centre
      @budget.update!(cost_centre: fringe_cost_centre)
      sign_in @user

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{debit_row}" }

      assert_response :success
      assert_equal @expense.record_id, assigns(:matched_debits).sole.last.record_id
    end

    # Budget#cost_centre_id is nullable, so most budgets have none: such an expense matches only while a
    # single centre is configured (the basic match test), and once a second exists we stop guessing.
    test "an expense with no cost centre stops matching once a second centre exists" do
      create_second_reimbursements_cost_centre
      sign_in @user

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{debit_row}" }

      assert_response :success
      assert_empty assigns(:matched_debits),
                   "an unattributed expense could belong to either pot, so we no longer guess"
      assert_equal 1, assigns(:unmatched_rows).size
    end

    # --- Dedup is per period AND per cost centre ---------------------------

    test "a stored row blocks a re-import in its own cost centre only" do
      create_second_reimbursements_cost_centre
      create_reimbursements_actual(nominal_code: "439999", period: "03", narrative: "Alice Producer",
                                   debit: BigDecimal("123.45"), cost_centre: fringe_cost_centre)
      sign_in @user

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{debit_row}\n#{debit_row(cost_centre: 'BED')}" }

      assert_equal %w[F40], assigns(:skipped_rows).map(&:cost_centre)
      assert_equal %w[BED], assigns(:new_rows).map(&:cost_centre),
                   "two pots can each carry the same charge in the same period"
    end

    # A stored row with no cost centre can't say which pot it is in: skipping a re-import leaves a
    # visible gap, importing a duplicate double-counts spend.
    test "a stored row with no cost centre of its own still blocks a re-import" do
      create_second_reimbursements_cost_centre
      create_reimbursements_actual(nominal_code: "439999", period: "03", narrative: "Alice Producer",
                                   debit: BigDecimal("123.45"))
      sign_in @user

      post :preview, params: { pasted_text: "#{ACTUALS_HEADER}\n#{debit_row(cost_centre: 'BED')}" }

      assert_response :success
      assert_equal 1, assigns(:skipped_rows).size
    end

    # The tickbox keys must survive the stateless round trip; this mimics what the preview form posts back.
    def offsetting_pair_keys(pasted_text, cost_centre: ::Reimbursements::CostCentre.default)
      rows = ::Reimbursements::Reconciliation.parse_actuals_rows(pasted_text)
      ::Reimbursements::Reconciliation
        .detect_offsetting_pairs(rows, cost_centres: rows.map { cost_centre.id.to_s })
        .map(&:key)
    end

    # --- Uploading the sheet -------------------------------------------------

    # The OLE2 signature every legacy .xls opens with, so +name+ can lie about the format like a renamed file.
    def actuals_legacy_xls(name: "actuals.xls")
      file = Tempfile.new([ "actuals", File.extname(name) ])
      file.binmode
      file.write("\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1".b + ("\x00".b * 64))
      file.rewind
      Rack::Test::UploadedFile.new(file.path, "application/vnd.ms-excel", original_filename: name)
    end

    # A .xlsx by name and first bytes (so not caught as legacy) that Roo still cannot open.
    def actuals_unreadable_xlsx
      file = Tempfile.new([ "actuals", ".xlsx" ])
      file.binmode
      file.write("not a zip at all")
      file.rewind
      Rack::Test::UploadedFile.new(file.path, "application/vnd.ms-excel",
                                   original_filename: "actuals.xlsx")
    end

    def actuals_csv(text)
      file = Tempfile.new([ "actuals", ".csv" ])
      file.write(text)
      file.rewind
      Rack::Test::UploadedFile.new(file.path, "text/csv")
    end

    # The wizard is stateless and an upload has no second file to re-send, so every form carrying the
    # sheet on to apply must hold it as TEXT (the apply form once carried params[:pasted_text], empty
    # on upload).
    test "an uploaded xlsx previews like a paste and is carried on as text" do
      sign_in @user

      post :preview, params: { actuals_file: xlsx_upload([ ACTUALS_HEADER.split("\t"), debit_row.split("\t") ], sheet: "Actuals") }

      assert_equal @expense.record_id, assigns(:matched_debits).sole.last.record_id
      carriers = css_select("input[name=pasted_text][type=hidden]")
      assert_not_empty carriers
      carriers.each { |field| assert_includes field["value"].to_s, "439999\tF40" }
    end

    test "a csv upload is read as the text it already is" do
      sign_in @user

      post :preview, params: { actuals_file: actuals_csv("#{ACTUALS_HEADER}\n#{debit_row}") }

      assert_response :success
      assert_match(/Alice Producer/, response.body)
    end

    test "a submit with neither a paste nor a file says so" do
      sign_in @user

      post :preview, params: { pasted_text: "" }

      assert_response :success
      assert_match(/Paste the actuals rows, or upload the sheet/, response.body)
    end

    # An operator holding a legacy file renames it .xlsx; the raw rubyzip message (tmp path included)
    # must not leak. The CONTENT decides, not the name.
    test "an .xls renamed .xlsx is still recognised as the older format" do
      error = assert_raises(::Reimbursements::ActualsUpload::UnreadableError) do
        ::Reimbursements::ActualsUpload.to_text(actuals_legacy_xls(name: "actuals.xlsx"))
      end

      assert_match(/older \.xls/, error.message)
      assert_no_match(/tmp|Zip|zip/, error.message)
    end

    # roo 3 dropped .xls and its raw message leaked a tmp path; each raise site is pinned to state a next step.
    test "every refusal states a next step" do
      upload = ::Reimbursements::ActualsUpload

      messages = [
        assert_raises(upload::UnreadableError) { upload.to_text(actuals_legacy_xls) }.message,
        assert_raises(upload::UnreadableError) { upload.to_text(xlsx_upload([ [] ], sheet: "Actuals")) }.message,
        assert_raises(upload::UnreadableError) { upload.to_text(actuals_unreadable_xlsx) }.message
      ]

      messages.each do |message|
        assert_match(/paste (the rows|them)/, message, message)
        assert_no_match(/extension option|tmp/, message, message)
        assert_no_match(/\.\./, message, "a doubled full stop: #{message}")
      end
    end

    # Every message carries its own advice, so the flash must not add a second copy.
    test "the flash states the advice once" do
      sign_in @user

      post :preview, params: { actuals_file: actuals_legacy_xls }

      message = response.body[/Couldn't read that file: [^"<]*/]
      assert_equal 1, message.scan(/paste the rows instead/).size, message
    end

    # A cell's own tab would split the row into two columns and shift every figure left, silently.
    test "a tab inside a spreadsheet cell cannot shift the row's columns" do
      # The tab has to be INSIDE one cell, which a row built by splitting on tabs would never show.
      cells = debit_row.split("\t")
      cells[5] = "Alice\tProducer"
      text = ::Reimbursements::ActualsUpload.to_text(xlsx_upload([ ACTUALS_HEADER.split("\t"), cells ], sheet: "Actuals"))

      assert_equal ACTUALS_HEADER.split("\t").size, text.lines.last.split("\t").size
      assert_includes text, "Alice Producer", "the tab becomes a space rather than a column break"
    end
  end
  end
end
