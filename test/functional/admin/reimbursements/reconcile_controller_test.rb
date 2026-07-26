require "test_helper"

module Admin
  module Reimbursements
  class ReconcileControllerTest < ActionController::TestCase
    include ReimbursementsTestHelpers

    HEADER = "Nominal\tCost Centre\tRef\tDate\tPeriod\tNarrative\tNarrative 1\tDebit\tCredit\tNet".freeze

    # DatabaseStore whose actual-link writes raise for chosen targets: one
    # row's transient write failure amid others that must still commit.
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

    # DatabaseStore that fails part-way through writing an offsetting pair: on
    # the second leg's insert, or on the cross-link that follows it.
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
      finance = Role.create!(name: "Business Manager")
      finance.permissions << Permission.create(action: "manage", subject_class: "reimbursements_finance")
      users(:member).add_role("Business Manager")
      @user = users(:member)

      # A Submitted expense that a debit row should match: nominal 439999,
      # excl-VAT 123.45, submitted to EUSA within 14 days of the actuals date.
      @person = create_reimbursements_person(name: "Alice Producer", email: "alice@example.com")
      @budget = create_reimbursements_budget(name: "Props", nominal_code: "439999")
      @income = create_reimbursements_budget(name: "Ticket income", nominal_code: "250000",
                                             budget_type: "Income")
      @expense = create_reimbursements_expense(
        person: @person, budget: @budget, amount: BigDecimal("123.45"),
        amount_excl_vat: BigDecimal("123.45"), status: ::Reimbursements::Status::SUBMITTED,
        submitted_to_eusa_date: Date.new(2026, 5, 10), receipt: false
      )

      # "You've been paid" emails go through the Graph notifier; inject a real
      # Notifier over a recording FakeGraphClient so tests assert the send.
      @graph = FakeGraphClient.new
      ReconcileController.notifier_builder =
        ->(cost_centre:) { ::Reimbursements::Notifier.new(cost_centre: cost_centre, graph: @graph) }
    end

    teardown do
      BaseController.store_builder = -> { ::Reimbursements.build_store }
      ReconcileController.notifier_builder =
        ->(cost_centre:) { ::Reimbursements::Notifier.new(cost_centre: cost_centre) }
    end

    def debit_row(nominal: "439999", date: "13/05/2026", period: "03", narrative: "Alice Producer",
                  debit: "123.45", cost_centre: "F40")
      "#{nominal}\t#{cost_centre}\tBACS001\t#{date}\t#{period}\t#{narrative}\tShow\t#{debit}\t\t#{debit}"
    end

    def credit_row(nominal: "250000", period: "03", narrative: "Box office", credit: "500.00",
                   cost_centre: "F40")
      "#{nominal}\t#{cost_centre}\tBACS002\t13/05/2026\t#{period}\t#{narrative}\tTickets\t\t#{credit}\t-#{credit}"
    end

    # A second cost centre, so the single-cost-centre shortcuts stop applying.
    def create_termtime_cost_centre
      ::Reimbursements::CostCentre.create!(key: "termtime", name: "Bedlam Termtime", eusa_code: "BED",
                                           receive_mailbox: "bed@example.com",
                                           send_mailbox: "bed@example.com")
    end

    def fringe_cost_centre
      ::Reimbursements::CostCentre.find_by!(eusa_code: "F40")
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

    # The cost-centre code used to fall back to a literal "F40", so with no cost
    # centre configured a paste was still filtered as though it were the Fringe's.
    # Now it says so instead of guessing: a guessed code would file another cost
    # centre's ledger under this one and every rollup would be quietly wrong.
    test "preview says so when no cost centre is configured, rather than assuming one" do
      sign_in @user
      ::Reimbursements::CostCentre.delete_all

      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row}" }

      assert_response :success
      assert_includes response.body, "No cost centre is set up yet"
      assert_nil assigns(:matched_debits)
    end

    test "preview matches a debit row to a submitted expense" do
      sign_in @user
      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row}" }

      assert_response :success
      assert_equal 1, assigns(:matched_debits).size
      row, expense = assigns(:matched_debits).first
      assert_equal @expense.record_id, expense.record_id
      assert_equal BigDecimal("123.45"), row.debit
      assert_empty assigns(:unmatched_rows)
    end

    test "preview matches a credit row to an income budget" do
      sign_in @user
      post :preview, params: { pasted_text: "#{HEADER}\n#{credit_row}" }

      assert_response :success
      assert_equal 1, assigns(:matched_credits).size
      _row, budget = assigns(:matched_credits).first
      assert_equal @income.record_id, budget.record_id
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
      assert_equal 0, ::Reimbursements::EusaActual.count
    end

    test "an expense with a payment_confirmed_date but no linked actual is excluded from matching" do
      @expense.update!(payment_confirmed_date: Date.new(2026, 5, 1))
      sign_in @user

      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row}" }

      assert_response :success
      assert_empty assigns(:matched_debits), "already-paid-by-another-route expenses must not be re-matched"
      assert_equal 1, assigns(:unmatched_rows).size
    end

    test "preview skips rows already imported for the same period" do
      create_reimbursements_actual(nominal_code: "439999", period: "03",
                                   narrative: "Alice Producer", debit: BigDecimal("123.45"))
      sign_in @user

      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row(period: '03')}" }

      assert_response :success
      assert_equal 1, assigns(:skipped_rows).size
      assert_empty assigns(:new_rows)
    end

    test "preview re-imports a matching row when it was imported under a different period" do
      # Same nominal/narrative/amount, but the imported copy is in period 02, so
      # the pasted period-03 row is new (dedup is scoped per EUSA period).
      create_reimbursements_actual(nominal_code: "439999", period: "02",
                                   narrative: "Alice Producer", debit: BigDecimal("123.45"))
      sign_in @user

      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row(period: '03')}" }

      assert_response :success
      assert_empty assigns(:skipped_rows)
      assert_equal 1, assigns(:new_rows).size
    end

    test "a single paste dedups each period independently" do
      # Period 03 already imported; period 04 is not. Re-pasting both keeps only
      # the period-04 row.
      create_reimbursements_actual(nominal_code: "439999", period: "03",
                                   narrative: "Alice Producer", debit: BigDecimal("123.45"))
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
      actual = ::Reimbursements::EusaActual.sole
      assert_equal [ @expense.record_id ], actual.linked_expense_ids
      # Expense flipped to Paid with a payment-confirmed date.
      @expense.reload
      assert_equal ::Reimbursements::Status::PAID, @expense.status
      assert_equal Date.new(2026, 5, 13), @expense.payment_confirmed_date
      assert_equal 1, assigns(:expenses_paid)
    end

    test "apply links a matched credit to its budget without emailing" do
      sign_in @user

      post :apply, params: { pasted_text: "#{HEADER}\n#{credit_row}" }

      assert_empty @graph.send_mails
      assert_response :success
      assert_equal [ @income.record_id ], ::Reimbursements::EusaActual.sole.linked_budget_ids
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
      assert_equal ::Reimbursements::Status::SUBMITTED, @expense.reload.status
    end

    test "apply skips a producer with no email" do
      @person.update!(email: nil)
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
      assert_equal ::Reimbursements::Status::PAID, @expense.reload.status
      assert_equal 1, assigns(:expenses_paid)
    end

    test "an already-reconciled expense is not re-matched or re-emailed by a later paste" do
      # @expense was already paid in an earlier period and linked to an imported
      # actual. A later/overlapping export carries a near-identical row (same
      # nominal/amount, matching date, but a slightly different narrative) so the
      # per-period dedup does NOT skip it. The re-pay guard must exclude the
      # already-linked expense so it can't be re-matched, re-paid, or re-emailed.
      @expense.update!(status: ::Reimbursements::Status::PAID)
      create_reimbursements_actual(nominal_code: "439999", period: "02",
                                   narrative: "Alice Producer OLD",
                                   debit: BigDecimal("123.45"), expense: @expense)
      sign_in @user

      post :apply, params: {
        pasted_text: "#{HEADER}\n#{debit_row(narrative: 'Alice Producer NEW')}"
      }

      assert_response :success
      assert_empty @graph.send_mails, "must not re-email a producer for an already-reconciled expense"
      assert_equal 0, assigns(:expenses_paid)
      assert_equal 1, assigns(:unmatched_saved)
      # The expense itself is left untouched — no second flip-to-Paid write.
      assert_nil @expense.reload.payment_confirmed_date
    end

    test "a mid-batch row failure doesn't abort the rest, and is surfaced instead of hidden" do
      second_expense = create_reimbursements_expense(
        person: @person, budget: @budget, amount: BigDecimal("55.00"),
        amount_excl_vat: BigDecimal("55.00"), status: ::Reimbursements::Status::SUBMITTED,
        submitted_to_eusa_date: Date.new(2026, 5, 10), nominal_code_override: "555555",
        receipt: false
      )
      # second_expense's link write fails (simulating a transient blip after its
      # Actual record was already created); @expense's row is untouched.
      BaseController.store_builder = -> { FlakyLinkStore.new(fail_expense_link_ids: [ second_expense.record_id ]) }
      sign_in @user

      post :apply, params: {
        pasted_text: "#{HEADER}\n#{debit_row}\n#{debit_row(nominal: '555555', narrative: 'Alice Producer', debit: '55.00')}"
      }

      assert_response :success
      # @expense committed fully (Paid + emailed); second_expense's failure
      # didn't abort it, and doesn't leave a silent "all good" report either.
      assert_equal 1, assigns(:expenses_paid)
      assert_equal [ "alice@example.com" ], @graph.send_mails.sole[:to]
      assert_equal ::Reimbursements::Status::PAID, @expense.reload.status
      assert_equal ::Reimbursements::Status::SUBMITTED, second_expense.reload.status
      assert_match(/expense #.*blip/i, assigns(:reconciliation_errors).sole)
      assert_match(/hit a problem/i, response.body)
    end

    test "a failed credit row is not counted in credits_linked" do
      BaseController.store_builder = -> { FlakyLinkStore.new(fail_budget_links: true) }
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

    # --- Offsetting pairs --------------------------------------------------
    #
    # An accrual and its reversal on the same nominal code and reference, a day
    # apart in consecutive periods: the shape that dominates a real EUSA export.

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
      "#{HEADER}\n#{accrual_row}\n#{reversal_row}"
    end

    test "preview proposes an offsetting pair instead of listing both legs as unmatched" do
      sign_in @user
      post :preview, params: { pasted_text: offsetting_paste }

      assert_response :success
      pair = assigns(:offsetting_pairs).sole
      assert_equal BigDecimal("500.00"), pair.debit_row.debit
      assert_equal BigDecimal("500.00"), pair.credit_row.credit
      assert_empty assigns(:unmatched_rows), "a paired row is not an unmatched row"
    end

    test "preview offers every proposed pair as a ticked checkbox the operator can untick" do
      sign_in @user
      post :preview, params: { pasted_text: offsetting_paste }

      assert_response :success
      key = assigns(:offsetting_pairs).sole.key
      assert_select "input[type=checkbox][name='offset_pair_keys[]'][value=?][checked=checked]", key
    end

    test "apply creates both legs, cross-links them, and stamps both offset" do
      sign_in @user
      keys = offsetting_pair_keys(offsetting_paste)

      post :apply, params: { pasted_text: offsetting_paste, offset_pair_keys: keys }

      assert_response :success
      assert_equal 2, ::Reimbursements::EusaActual.count, "both legs are kept for the audit trail"
      legs = ::Reimbursements::EusaActual.order(:id).to_a
      assert legs.all?(&:offset?)
      assert_equal legs.last.id, legs.first.offset_of_id
      assert_equal legs.first.id, legs.last.offset_of_id
      assert_equal 1, assigns(:offsets_linked)
      assert_equal 0, assigns(:unmatched_saved)
    end

    test "an unticked pair is imported as two ordinary rows instead" do
      sign_in @user

      post :apply, params: { pasted_text: offsetting_paste, offset_pair_keys: [ "" ] }

      assert_response :success
      assert_equal 2, ::Reimbursements::EusaActual.count
      assert ::Reimbursements::EusaActual.none?(&:offset?),
             "unticking the pair must leave both rows as ordinary unlinked actuals"
      assert_equal 0, assigns(:offsets_linked)
      assert_equal 2, assigns(:unmatched_saved)
    end

    # The whole point of pairing: an accrual leg that happens to look like a
    # real claim must not pay that claim. Only rows left OUT of a pair reach the
    # debit-to-expense matcher.
    test "an applied pair's legs never match (or pay) an expense" do
      lookalike = create_reimbursements_expense(
        person: @person, budget: @budget, amount: BigDecimal("500.00"),
        amount_excl_vat: BigDecimal("500.00"), status: ::Reimbursements::Status::SUBMITTED,
        submitted_to_eusa_date: Date.new(2026, 4, 27), nominal_code_override: ACCRUAL_NOMINAL,
        receipt: false
      )
      sign_in @user
      keys = offsetting_pair_keys(offsetting_paste)

      post :apply, params: { pasted_text: offsetting_paste, offset_pair_keys: keys }

      assert_response :success
      assert_equal ::Reimbursements::Status::SUBMITTED, lookalike.reload.status
      assert_nil lookalike.payment_confirmed_date
      assert_equal 0, assigns(:expenses_paid)
      assert_empty @graph.send_mails
    end

    # Unticking hands the legs back to the ordinary matcher, so a leg that does
    # match an expense pays it — the operator's judgement, not the heuristic's.
    test "unticking a pair returns its legs to the ordinary debit matching" do
      lookalike = create_reimbursements_expense(
        person: @person, budget: @budget, amount: BigDecimal("500.00"),
        amount_excl_vat: BigDecimal("500.00"), status: ::Reimbursements::Status::SUBMITTED,
        submitted_to_eusa_date: Date.new(2026, 4, 27), nominal_code_override: ACCRUAL_NOMINAL,
        receipt: false
      )
      sign_in @user

      post :apply, params: { pasted_text: offsetting_paste, offset_pair_keys: [ "" ] }

      assert_response :success
      assert_equal ::Reimbursements::Status::PAID, lookalike.reload.status
      assert_equal 1, assigns(:expenses_paid)
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
    # preview counts matched expenses over the UNPAIRED rows only, while apply
    # hands an unticked pair's legs back to the ordinary matching and can pay
    # (and email) expenses the confirmation never mentioned. Each pair therefore
    # states what unticking it would cost.

    def lookalike_expense
      create_reimbursements_expense(
        person: @person, budget: @budget, amount: BigDecimal("500.00"),
        amount_excl_vat: BigDecimal("500.00"), status: ::Reimbursements::Status::SUBMITTED,
        submitted_to_eusa_date: Date.new(2026, 4, 27), nominal_code_override: ACCRUAL_NOMINAL,
        receipt: false
      )
    end

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

    test "the preview says nothing about a pair whose legs match nothing" do
      sign_in @user

      post :preview, params: { pasted_text: offsetting_paste }

      assert_response :success
      assert_nil assigns(:offset_pair_consequences)[assigns(:offsetting_pairs).sole.key][:expense]
      assert_no_match(/if you untick/i, response.body)
    end

    # Two pairs that both look like the same expense must not both claim it:
    # apply matches each expense once, so the preview has to as well.
    test "two identical pairs never both claim the same expense if unticked" do
      lookalike_expense
      sign_in @user

      post :preview, params: { pasted_text: [ HEADER, accrual_row, reversal_row,
                                              accrual_row, reversal_row ].join("\n") }

      assert_response :success
      claimed = assigns(:offset_pair_consequences).values.filter_map { |c| c[:expense] }
      assert_equal 1, claimed.size, "the second pair has no expense left to pay"
    end

    # --- A pair is written all-or-nothing ----------------------------------
    #
    # A half-written pair is the worst state available: the debit leg is
    # committed WITHOUT the offset stamp, so every rollup reads it as real
    # spend, and re-pasting cannot repair it because dedup then skips that leg
    # and the pair can never be re-formed. Both legs and the cross-link are one
    # transaction.

    test "a pair whose second leg fails to insert writes neither leg" do
      BaseController.store_builder = -> { HalfPairStore.new(fail_on: :second_leg) }
      sign_in @user
      keys = offsetting_pair_keys(offsetting_paste)

      post :apply, params: { pasted_text: offsetting_paste, offset_pair_keys: keys }

      assert_response :success
      assert_equal 0, ::Reimbursements::EusaActual.count,
                   "a stranded unstamped debit leg would read as real spend forever"
      assert_equal 0, assigns(:offsets_linked)
      assert_match(/offsetting pair.*blip/i, assigns(:reconciliation_errors).sole)
    end

    test "a pair whose cross-link fails writes neither leg" do
      BaseController.store_builder = -> { HalfPairStore.new(fail_on: :link) }
      sign_in @user
      keys = offsetting_pair_keys(offsetting_paste)

      post :apply, params: { pasted_text: offsetting_paste, offset_pair_keys: keys }

      assert_response :success
      assert_equal 0, ::Reimbursements::EusaActual.count,
                   "two unlinked ordinary actuals are exactly what the pair transaction prevents"
      assert_equal 0, assigns(:offsets_linked)
    end

    # --- Duplicate pairs ---------------------------------------------------
    #
    # A paste really can contain the same £10 accrual and reversal twice: two
    # separate transactions, two separate pairs. They must get two tickboxes,
    # because ticking one and unticking the other has to mean exactly that.

    def duplicate_pairs_paste
      accrual = accrual_row(amount: "10.00")
      reversal = reversal_row(amount: "10.00")
      [ HEADER, accrual, reversal, accrual, reversal ].join("\n")
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
    #
    # The wizard used to filter a paste down to ONE cost-centre code and drop
    # every other row in silence. The export names the cost centre per row, so
    # each row now lands where its own code says.

    test "a paste spanning two cost centres imports every row under its own" do
      termtime = create_termtime_cost_centre
      sign_in @user
      paste = [ HEADER, debit_row(narrative: "Fringe spend"),
                debit_row(narrative: "Termtime spend", cost_centre: "BED") ].join("\n")

      post :apply, params: { pasted_text: paste }

      assert_response :success
      actuals = ::Reimbursements::EusaActual.order(:id).to_a
      assert_equal 2, actuals.size
      assert_equal [ fringe_cost_centre.id, termtime.id ], actuals.map(&:cost_centre_id)
      assert_equal %w[F40 BED], actuals.map { |actual| actual.cost_centre.eusa_code },
                   "each row resolves through the association to the pot its own code named"
    end

    test "an imported row records the cost centre it resolved to as a real association" do
      sign_in @user

      post :apply, params: { pasted_text: "#{HEADER}\n#{debit_row}" }

      assert_equal fringe_cost_centre, ::Reimbursements::EusaActual.sole.cost_centre
    end

    # Another society's spend in a whole-organisation export. Skipping it is
    # right; skipping it silently is the bug this replaces.
    test "preview reports the rows it skipped for an unconfigured cost centre, and names the codes" do
      sign_in @user
      paste = [ HEADER, debit_row, debit_row(narrative: "Someone else", cost_centre: "G12"),
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
      paste = [ HEADER, debit_row, debit_row(narrative: "Someone else", cost_centre: "G12") ].join("\n")

      post :apply, params: { pasted_text: paste }

      assert_response :success
      assert_equal [ fringe_cost_centre.id ], ::Reimbursements::EusaActual.pluck(:cost_centre_id)
      assert_match(/not set up here/, response.body)
    end

    # --- Blank cost centres always need an explicit answer -----------------

    def blank_centre_paste
      [ HEADER, debit_row, debit_row(narrative: "No centre named", cost_centre: "") ].join("\n")
    end

    # Not inferred even here, where the fixture is the only cost centre in the
    # database: "it must be the only one" is exactly the guess that files real
    # spend under the wrong pot the day a second pot exists.
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
      assert_empty @graph.send_mails
      assert_match(/no cost centre of their own/, response.body)
    end

    test "a chosen cost centre imports the blank rows under it" do
      termtime = create_termtime_cost_centre
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

    test "an unknown cost centre id reads as no answer at all" do
      sign_in @user

      post :apply, params: { pasted_text: blank_centre_paste, blank_cost_centre_id: "999999" }

      assert_response :success
      assert_equal 0, ::Reimbursements::EusaActual.count
    end

    # --- Offsetting pairs never span cost centres --------------------------
    #
    # A false positive here stamps two unrelated real transactions as cancelling
    # out, hiding real spend from BOTH pots' rollups with no way back except the
    # "Not offsetting" button. A false negative just leaves two visible rows.

    test "an accrual and a reversal in different cost centres are never paired" do
      create_termtime_cost_centre
      sign_in @user
      paste = [ HEADER, accrual_row, reversal_row(cost_centre: "BED") ].join("\n")

      post :preview, params: { pasted_text: paste }

      assert_response :success
      assert_empty assigns(:offsetting_pairs)
      assert_equal 2, assigns(:unmatched_rows).size
    end

    test "the same pair inside one cost centre still forms" do
      create_termtime_cost_centre
      sign_in @user

      post :preview, params: { pasted_text: offsetting_paste }

      assert_response :success
      assert_equal 1, assigns(:offsetting_pairs).size
    end

    # --- Matching is scoped to the row's cost centre -----------------------

    test "a debit row never matches an expense whose budget is in another cost centre" do
      @budget.update!(cost_centre: create_termtime_cost_centre)
      sign_in @user

      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row}" }

      assert_response :success
      assert_empty assigns(:matched_debits),
                   "a Fringe debit must not pay (and email about) a termtime claim"
      assert_equal 1, assigns(:unmatched_rows).size
    end

    test "a debit row matches an expense whose budget is in its own cost centre" do
      create_termtime_cost_centre
      @budget.update!(cost_centre: fringe_cost_centre)
      sign_in @user

      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row}" }

      assert_response :success
      assert_equal @expense.record_id, assigns(:matched_debits).sole.last.record_id
    end

    test "a credit row never matches an income budget in another cost centre" do
      @income.update!(cost_centre: create_termtime_cost_centre)
      sign_in @user

      post :preview, params: { pasted_text: "#{HEADER}\n#{credit_row}" }

      assert_response :success
      assert_empty assigns(:matched_credits)
      assert_equal 1, assigns(:unmatched_rows).size
    end

    # Budget#cost_centre_id is nullable and predates this scoping, so most
    # existing budgets have none. While a single cost centre is configured there
    # is nowhere else such an expense could belong, so it still matches; once a
    # second centre exists the ambiguity is real and we stop guessing.
    test "an expense with no cost centre still matches while only one centre is configured" do
      assert_nil @budget.cost_centre_id
      sign_in @user

      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row}" }

      assert_response :success
      assert_equal 1, assigns(:matched_debits).size
    end

    test "an expense with no cost centre stops matching once a second centre exists" do
      create_termtime_cost_centre
      sign_in @user

      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row}" }

      assert_response :success
      assert_empty assigns(:matched_debits),
                   "an unattributed expense could belong to either pot, so we no longer guess"
      assert_equal 1, assigns(:unmatched_rows).size
    end

    # --- Dedup is per period AND per cost centre ---------------------------

    test "an identical row in another cost centre is not deduped away" do
      termtime = create_termtime_cost_centre
      create_reimbursements_actual(nominal_code: "439999", period: "03", narrative: "Alice Producer",
                                   debit: BigDecimal("123.45"), cost_centre: fringe_cost_centre)
      sign_in @user

      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row(cost_centre: 'BED')}" }

      assert_response :success
      assert_empty assigns(:skipped_rows),
                   "two pots can each carry the same charge in the same period"
      assert_equal 1, assigns(:new_rows).size
      assert_equal termtime.eusa_code, "BED"
    end

    test "the same row in the same cost centre is still deduped away" do
      create_termtime_cost_centre
      create_reimbursements_actual(nominal_code: "439999", period: "03", narrative: "Alice Producer",
                                   debit: BigDecimal("123.45"), cost_centre: fringe_cost_centre)
      sign_in @user

      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row}" }

      assert_response :success
      assert_equal 1, assigns(:skipped_rows).size
    end

    # A row imported before this column existed can't say which pot it is in, and
    # here the asymmetry runs the other way from the pairing heuristic: skipping
    # a re-import leaves a visible gap, whereas importing a duplicate silently
    # double-counts real spend in the ledger and every rollup.
    test "a stored row with no cost centre of its own still blocks a re-import" do
      create_termtime_cost_centre
      create_reimbursements_actual(nominal_code: "439999", period: "03", narrative: "Alice Producer",
                                   debit: BigDecimal("123.45"))
      sign_in @user

      post :preview, params: { pasted_text: "#{HEADER}\n#{debit_row(cost_centre: 'BED')}" }

      assert_response :success
      assert_equal 1, assigns(:skipped_rows).size
    end

    # Preview and apply both re-derive the pairs from the pasted text (the
    # wizard keeps no session state), so the tickbox keys must survive the round
    # trip. The helper mimics what the preview form posts back.
    def offsetting_pair_keys(pasted_text, cost_centre: ::Reimbursements::CostCentre.default)
      rows = ::Reimbursements::Reconciliation.parse_actuals_rows(pasted_text)
      ::Reimbursements::Reconciliation
        .detect_offsetting_pairs(rows, cost_centres: rows.map { cost_centre.id.to_s })
        .first.map(&:key)
    end
  end
  end
end
