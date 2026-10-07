module Admin
  module Reimbursements
    ##
    # EUSA actuals reconciliation, a three-step wizard: paste the export (show); preview (attribute each
    # row to the cost centre its own Cost Centre column names, dedup, propose offsetting pairs, match the
    # rest); apply (write the actuals, link them, mark matched expenses Paid). Stateless: preview and apply
    # re-parse the pasted text carried in the form, so apply always re-checks a fresh actuals list.
    #
    # NOTHING IS EMAILED TO THE PRODUCER HERE. Actuals land weeks after the BACS run they confirm, so a
    # "you've been paid" note is old news; Paid is bookkeeping, not an event.
    #
    # A paste may span several cost centres, each row landing in the one it names (see
    # Reimbursements::ActualsAttribution). Filtering to one code would lose the rest silently.
    #
    # Gated by the finance grid permission (`:manage, :reimbursements_finance`).
    class ReconcileController < FinanceController
      NOTHING_GIVEN_ALERT =
        "Paste the actuals rows, or upload the sheet, before parsing.".freeze

      NO_COST_CENTRE_ALERT =
        "No cost centre is set up yet, so there is nothing to reconcile these rows against. " \
        "Add one under Settings first.".freeze

      BLANK_CHOICE_ALERT =
        "Nothing was applied. Some rows have no cost centre of their own, so you have to say " \
        "which cost centre they belong to (or skip them) before this paste can be imported.".freeze

      before_action { @title = "Reconcile EUSA actuals" }

      def show; end

      def preview
        # An upload beats the text box and is converted to text once: apply only ever sees the
        # hidden-field text, and an upload has no second file to re-send.
        @pasted_text = text_from_upload || params[:pasted_text].to_s
        return render :show if @upload_error

        if @pasted_text.blank?
          flash.now[:alert] = NOTHING_GIVEN_ALERT
          return render :show
        end

        parsed = parse_rows(@pasted_text)
        return render :show if parsed.nil?

        if parsed.empty?
          flash.now[:alert] = "No data rows found in the pasted text (only a header?)."
          return render :show
        end

        attribution = attribute(parsed)
        if attribution.nil?
          flash.now[:alert] = NO_COST_CENTRE_ALERT
          return render :show
        end

        build_preview(attribution)
        render :preview
      end

      def apply
        @pasted_text = params[:pasted_text].to_s

        if @pasted_text.blank?
          redirect_to admin_reimbursements_reconciliation_path,
                      alert: "Nothing to apply. Start again from the paste step."
          return
        end

        parsed = parse_rows(@pasted_text)
        if parsed.nil?
          redirect_to admin_reimbursements_reconciliation_path,
                      alert: "Could not parse the actuals. Start again from the paste step."
          return
        end

        attribution = attribute(parsed)
        if attribution.nil?
          redirect_to admin_reimbursements_reconciliation_path, alert: NO_COST_CENTRE_ALERT
          return
        end

        # An unanswered blank-cost-centre question blocks the WHOLE paste, and the preview is re-rendered,
        # not redirected, so a large paste survives the refusal.
        if attribution.blank_choice_required?
          flash.now[:alert] = BLANK_CHOICE_ALERT
          build_preview(attribution)
          return render :preview
        end

        commit(attribution)
        render :apply
      end

      private

      # Shared with apply's refusal path, so a blocked apply lands on a working preview.
      def build_preview(attribution)
        @attribution = attribution
        @cost_centres = configured_cost_centres
        new_entries, skipped_entries = dedup(attribution.attributed)
        @new_rows = new_entries.map(&:row)
        @skipped_rows = skipped_entries.map(&:row)
        @offsetting_pairs = detect_pairs(new_entries)
        unpaired = entries_outside(new_entries, @offsetting_pairs)
        matched_debits, matched_credits, unmatched = build_matches(unpaired)
        @matched_debits = matched_debits.map { |entry, expense| [ entry.row, expense ] }
        @matched_credits = matched_credits.map { |entry, budget| [ entry.row, budget ] }
        @unmatched_rows = unmatched.map(&:row)
        @offset_pair_consequences =
          offset_pair_consequences(@offsetting_pairs, new_entries, matched_debits)
      end

      # Write everything this paste decided, and report only what committed.
      def commit(attribution)
        @attribution = attribution
        new_entries, skipped_entries = dedup(attribution.attributed)
        @skipped_count = skipped_entries.size

        # An unticked pair's legs go back into ordinary matching.
        ticked = ticked_offset_pair_keys
        pairs = detect_pairs(new_entries).select { |pair| ticked.include?(pair.key) }
        matched_debits, matched_credits, unmatched = build_matches(entries_outside(new_entries, pairs))

        imported_at = Time.current
        @offsets_linked = pairs.count { |pair| apply_offsetting_pair(new_entries, pair, imported_at) }
        @expenses_paid = matched_debits.count { |entry, expense| apply_debit_row(entry, expense, imported_at) }
        @credits_linked = matched_credits.count { |entry, budget| apply_credit_row(entry, budget, imported_at) }
        @unmatched_saved = unmatched.count { |entry| apply_unmatched_row(entry, imported_at) }
      end

      # The uploaded sheet as text, or nil when no file was picked. An unreadable file is reported on
      # the form, not as a 500 that loses the upload.
      def text_from_upload
        file = params[:actuals_file]
        return nil unless file.respond_to?(:path)

        ::Reimbursements::ActualsUpload.to_text(file)
      rescue ::Reimbursements::ActualsUpload::UnreadableError => e
        @upload_error = true
        # e.message already carries the advice.
        flash.now[:alert] = "Couldn't read that file: #{e.message}"
        nil
      end

      def parse_rows(text)
        ::Reimbursements::Reconciliation.parse_actuals_rows(text)
      rescue ArgumentError => e
        flash.now[:alert] = "Could not parse actuals: #{e.message}"
        nil
      end

      # Nil when no cost centre is configured: inventing a code would file money under a pot that
      # doesn't exist.
      def attribute(rows)
        return nil if configured_cost_centres.empty?

        ::Reimbursements::ActualsAttribution
          .new(cost_centres: configured_cost_centres)
          .call(rows, blank_choice: params[:blank_cost_centre_id])
      end

      def configured_cost_centres
        @configured_cost_centres ||= ::Reimbursements::CostCentre.order(:id).to_a
      end

      # Splits attributed rows into [new, already-imported] by dedup key against the actuals stored for
      # the same EUSA period AND cost centre. The centre is in the bucket key because two pots can carry
      # the same charge in one period. A STORED row with no cost centre counts in EVERY centre's bucket:
      # skipping a re-import leaves a visible gap, importing a duplicate double-counts spend (the
      # asymmetry runs the other way from pairing).
      def dedup(entries)
        existing = Hash.new do |cache, key|
          period, cost_centre_id = key
          cache[key] = store.actuals_for_period(period)
                            .select { |a| a[:cost_centre_id].nil? || a[:cost_centre_id] == cost_centre_id }
                            .map(&:dedup_key).to_set
        end
        entries.partition do |entry|
          row = entry.row
          key = ::Reimbursements::Reconciliation.actuals_row_dedup_key(
            row.nominal_code, row.narrative, row.debit, row.credit
          )
          !existing[[ row.period, entry.cost_centre.id ]].include?(key)
        end
      end

      # Offsetting pairs within a cost centre, so two pots' unrelated transactions never cancel. The
      # identities are the resolved centre ids, not exported codes, so a blank-code row the operator
      # assigned pairs as a member of its pot.
      def detect_pairs(entries)
        ::Reimbursements::Reconciliation.detect_offsetting_pairs(
          entries.map(&:row), cost_centres: entries.map { |entry| entry.cost_centre.id.to_s }
        )
      end

      # The pair keys left ticked. Each proposed pair posts a blank hidden entry beside its checkbox, so
      # an absent key means unticked, never "we didn't ask".
      def ticked_offset_pair_keys
        keys = params[:offset_pair_keys]
        return Set.new unless keys.is_a?(Array)

        keys.map(&:to_s).compact_blank.to_set
      end

      # Entries not consumed by the pairs, in paste order. Keyed on row INDEXES, not equality: two
      # byte-identical rows are two transactions.
      def entries_outside(entries, pairs)
        consumed = pairs.flat_map { |pair| [ pair.debit_index, pair.credit_index ] }.to_set
        entries.each_with_index.reject { |_entry, index| consumed.include?(index) }.map(&:first)
      end

      # Matches debits to Submitted/Paid expenses (each claimed at most once) and credits to income
      # budgets. Returns [matched_debits, matched_credits, unmatched]; a match is [entry, expense|budget].
      # Both are scoped to the row's cost centre: a termtime debit must not mark a Fringe claim Paid.
      def build_matches(entries)
        remaining = matchable_expenses
        income_budgets = income_budgets_pool

        matched_debits = []
        matched_credits = []
        unmatched = []

        entries.each do |entry|
          row = entry.row
          if row.debit.positive?
            expense = ::Reimbursements::Reconciliation.match_debit_to_expense(
              row, expenses_in(entry.cost_centre, remaining)
            )
            if expense
              matched_debits << [ entry, expense ]
              remaining.delete(expense)
            else
              unmatched << entry
            end
          elsif row.credit.positive?
            budget = ::Reimbursements::Reconciliation.match_credit_to_budget(
              row, budgets_in(entry.cost_centre, income_budgets)
            )
            budget ? matched_credits << [ entry, budget ] : unmatched << entry
          else
            unmatched << entry
          end
        end

        [ matched_debits, matched_credits, unmatched ]
      end

      # Every expense a debit may match, as a fresh array the caller consumes from (a matched expense is
      # deleted). Cost centre scoping is per row (expenses_in) from this one pool, so an expense claimed
      # by any row is out of reach of every other row. Submitted or Paid, and neither linked to an
      # imported actual nor payment-confirmed: dedup only catches an identical row, so a near-duplicate
      # would otherwise pay a claim twice.
      def matchable_expenses
        reconciled = store.eusa_actuals.filter_map { |actual| actual.expense_id&.to_s }.to_set
        store.expenses.select do |e|
          e.status.in?([ ::Reimbursements::Status::SUBMITTED, ::Reimbursements::Status::PAID ]) &&
            e.payment_confirmed_date.blank? && !reconciled.include?(e.record_id)
        end
      end

      def income_budgets_pool
        store.budgets.select(&:income?)
      end

      # An expense reaches its cost centre through its budget (Budget#cost_centre_id).
      def expenses_in(cost_centre, expenses)
        expenses.select { |expense| in_cost_centre?(expense.budget&.cost_centre_id, cost_centre) }
      end

      def budgets_in(cost_centre, budgets)
        budgets.select { |budget| in_cost_centre?(budget.cost_centre_id, cost_centre) }
      end

      # A record with no cost centre (no budget, or a nil Budget#cost_centre_id) belongs to the row's
      # centre only while exactly one centre is configured. Once a second exists, stop guessing: the row
      # lists as unmatched until someone gives its budget a centre, instead of paying the wrong pot.
      def in_cost_centre?(record_cost_centre_id, cost_centre)
        return record_cost_centre_id == cost_centre.id if record_cost_centre_id

        configured_cost_centres.one?
      end

      # What unticking each pair would do, as { pair key => { expense:, budget: } }. The "mark N matched
      # expenses Paid" count covers unpaired rows only, but an unticked pair's legs go back to ordinary
      # matching, so naming the expense each tick decides is more use than a corrected total. Pairs
      # consume from the pool the ordinary matching left, in order, so two lookalike pairs never both
      # promise the same expense; each leg is scoped to its own entry's cost centre.
      def offset_pair_consequences(pairs, entries, matched_debits)
        claimed = matched_debits.map { |_entry, expense| expense.record_id }.to_set
        remaining = matchable_expenses.reject { |e| claimed.include?(e.record_id) }
        budgets = income_budgets_pool

        pairs.to_h do |pair|
          cost_centre = entries[pair.debit_index].cost_centre
          expense = ::Reimbursements::Reconciliation.match_debit_to_expense(
            pair.debit_row, expenses_in(cost_centre, remaining)
          )
          remaining.delete(expense) if expense
          budget = ::Reimbursements::Reconciliation.match_credit_to_budget(
            pair.credit_row, budgets_in(entries[pair.credit_index].cost_centre, budgets)
          )
          [ pair.key, { expense: expense, budget: budget } ]
        end
      end

      # Both legs are imported and cross-linked in one store call; see
      # DatabaseStore#create_offsetting_pair! for why a half-written pair is unrepairable.
      def apply_offsetting_pair(entries, pair, imported_at)
        with_row_rescue("an offsetting pair") do
          store.create_offsetting_pair!(actuals_attrs(entries[pair.debit_index], imported_at),
                                        actuals_attrs(entries[pair.credit_index], imported_at))
        end
      end

      def apply_debit_row(entry, expense, imported_at)
        with_row_rescue("expense ##{expense.auto_number}") do
          actual = store.create_actual!(actuals_attrs(entry, imported_at))
          # gbp_charged corrects an international claim's estimate; the store ignores it on a UK claim.
          store.settle_expense_from_actual!(actual.record_id, expense.record_id,
                                            payment_date: entry.row.date,
                                            gbp_charged: entry.row.debit)
        end
      end

      def apply_credit_row(entry, budget, imported_at)
        with_row_rescue("budget #{budget.display_name}") do
          actual = store.create_actual!(actuals_attrs(entry, imported_at))
          store.link_actual_to_budget!(actual.record_id, budget.record_id)
        end
      end

      def apply_unmatched_row(entry, imported_at)
        with_row_rescue("an unmatched row") do
          store.create_actual!(actuals_attrs(entry, imported_at))
        end
      end

      # One row's failure must not abort the paste: a 500 after rows 1..k-1 committed leaves a partly
      # applied paste with nothing on screen saying so. The rest still commits, the failed row is named,
      # and the counts cover only what committed. Re-pasting cannot reveal it either, since committed
      # rows read as already imported.
      def with_row_rescue(subject)
        yield
        true
      rescue StandardError => e
        log_and_notify("Reimbursements: reconciliation row failed for #{subject} — #{e.message}", e,
                       context: { source: "reimbursements_reconciliation_apply", subject: subject })
        (@reconciliation_errors ||= []) << "#{subject}: #{e.message}"
        false
      end

      # source_month is never written (the EUSA period scopes). The cost centre is stored as the
      # resolved FK only: the exported code is the input to attribution, and storing it beside the
      # answer would let the two disagree.
      def actuals_attrs(entry, imported_at)
        row = entry.row
        {
          nominal_code: row.nominal_code, cost_centre_id: entry.cost_centre.id, ref: row.ref,
          date: row.date, period: row.period, narrative: row.narrative,
          narrative_1: row.narrative_1, debit: row.debit, credit: row.credit, net: row.net,
          imported_at: imported_at
        }
      end
    end
  end
end
