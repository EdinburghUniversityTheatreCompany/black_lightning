module Admin
  module Reimbursements
    ##
    # EUSA actuals reconciliation for the finance team. Ports bedlam-bacs
    # `pages/6_Reconcile.py`: a three-step wizard.
    #
    #   1. show    — paste the monthly EUSA actuals export.
    #   2. preview — parse (legacy/Sage auto-detect), ATTRIBUTE each row to the
    #                cost centre its own Cost Centre column names, dedup against
    #                rows already imported for the same EUSA period + cost
    #                centre, propose the offsetting pairs (an accrual and its
    #                reversal), and match the rest — debits to Submitted/Paid
    #                expenses, credits to income budgets, both scoped to the
    #                row's cost centre.
    #   3. apply   — create EUSA Actuals records, link them to the matched
    #                expense/budget, cross-link the offsetting pairs the
    #                operator left ticked, mark matched expenses Paid, and email
    #                the producers "you've been paid".
    #
    # PER-ROW COST CENTRES. The wizard used to filter a paste down to ONE code
    # (a hardcoded "F40", later CostCentre.default) and silently drop the rest,
    # so a whole-organisation or termtime export lost its other centres with
    # nothing on screen to explain it. The export already carries the answer per
    # row, so nobody has to tell it: see Reimbursements::ActualsAttribution for
    # the three outcomes (attributed / unrecognised code, skipped visibly /
    # blank code, needing an explicit operator choice).
    #
    # The wizard is stateless: preview/apply re-parse the pasted text carried in
    # the form (the parse + match functions are pure), so nothing is stashed in
    # the session and the dedup on apply always re-checks a fresh actuals list.
    # The operator's blank-row choice therefore travels in the form too, the way
    # the offsetting-pair ticks do — and apply refuses to commit anything while
    # that answer is missing, because quietly dropping the rows at the commit
    # step is exactly the silent loss this change removes.
    #
    # Dedup keys off each row's own EUSA period AND cost centre, so a single
    # paste spanning several of either is deduped bucket-by-bucket rather than as
    # one block.
    #
    # Gated by the finance grid permission (`:manage, :reimbursements_finance`).
    class ReconcileController < FinanceController
      NO_COST_CENTRE_ALERT =
        "No cost centre is set up yet, so there is nothing to reconcile these rows against. " \
        "Add one under Settings first.".freeze

      BLANK_CHOICE_ALERT =
        "Nothing was applied. Some rows have no cost centre of their own, so you have to say " \
        "which cost centre they belong to (or skip them) before this paste can be imported.".freeze

      def show
        @title = "Reconcile EUSA actuals"
      end

      def preview
        @title = "Reconcile EUSA actuals"
        @pasted_text = params[:pasted_text].to_s

        return render :show if @pasted_text.strip.empty?

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

        unless @pasted_text.strip.present?
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

        # An unanswered blank-cost-centre question blocks the WHOLE paste rather
        # than quietly importing the rows that do have a centre: the operator
        # cannot be shown a confirmation and then have rows disappear behind it.
        # The preview is re-rendered rather than redirected to, so a 300-row
        # paste survives the refusal.
        if attribution.blank_choice_required?
          @title = "Reconcile EUSA actuals"
          flash.now[:alert] = BLANK_CHOICE_ALERT
          build_preview(attribution)
          return render :preview
        end

        commit(attribution)
        render :apply
      end

      private

      # Everything preview shows, from an attributed paste. Shared with apply's
      # refusal path so a blocked apply lands the operator back on a working
      # preview instead of an empty form.
      def build_preview(attribution)
        @attribution = attribution
        @cost_centres = configured_cost_centres
        new_entries, skipped_entries = dedup(attribution.attributed)
        @new_rows = new_entries.map(&:row)
        @skipped_rows = skipped_entries.map(&:row)
        @offsetting_pairs, = detect_pairs(new_entries)
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

        # Only the pairs the operator left ticked are collapsed; an unticked
        # pair's legs go back into the ordinary matching as genuine rows.
        pairs, = detect_pairs(new_entries)
        applied_pairs = pairs.select { |pair| ticked_offset_pair_keys.include?(pair.key) }
        matched_debits, matched_credits, unmatched =
          build_matches(entries_outside(new_entries, applied_pairs))

        committed_pairs, committed_debits, committed_credits, committed_unmatched =
          apply_reconciliation(new_entries, applied_pairs, matched_debits, matched_credits, unmatched)
        notify_paid_producers(committed_debits)

        @offsets_linked = committed_pairs.size
        @expenses_paid = committed_debits.size
        @credits_linked = committed_credits.size
        @unmatched_saved = committed_unmatched.size
      end

      def parse_rows(text)
        ::Reimbursements::Reconciliation.parse_actuals_rows(text)
      rescue ArgumentError => e
        flash.now[:alert] = "Could not parse actuals: #{e.message}"
        nil
      end

      # Attribute each parsed row to the cost centre its own code names, or nil
      # when none is configured at all (there is then nothing to reconcile
      # against, and inventing a code would file real money under a pot that
      # doesn't exist).
      def attribute(rows)
        return nil if configured_cost_centres.empty?

        ::Reimbursements::ActualsAttribution
          .new(cost_centres: configured_cost_centres)
          .call(rows, blank_choice: params[:blank_cost_centre_id])
      end

      def configured_cost_centres
        @configured_cost_centres ||= ::Reimbursements::CostCentre.order(:id).to_a
      end

      # Split attributed rows into [new, already-imported] using the dedup key
      # against the actuals already stored for the same EUSA period AND cost
      # centre.
      #
      # The cost centre had to join the period in the bucket key the moment one
      # paste could span several centres: two centres can each carry a row with
      # the same nominal code, narrative and amount in the same period (a shared
      # supplier charge split between pots, the same recurring journal), and on a
      # period-only key the second centre's row reads as "already imported" and
      # vanishes — the silent drop this whole change removes, reappearing one
      # layer down.
      #
      # A STORED row with no cost centre of its own (imported before this column
      # existed, or with a blank code) is counted in EVERY centre's bucket. It
      # cannot say which pot it belongs to, and here the asymmetry runs the other
      # way from the offsetting-pair heuristic: skipping a re-import leaves a
      # visible gap in a paste, whereas importing a duplicate double-counts real
      # spend in the ledger and every rollup.
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

      # Offsetting pairs over the attributed rows, gated to within a cost centre:
      # two unrelated real transactions in two pots must never be stamped as
      # cancelling each other out. The identities are the resolved cost centre
      # ids, not the exported codes, so a blank-code row the operator assigned to
      # a pot pairs as a member of that pot.
      def detect_pairs(entries)
        ::Reimbursements::Reconciliation.detect_offsetting_pairs(
          entries.map(&:row), cost_centres: entries.map { |entry| entry.cost_centre.id.to_s }
        )
      end

      # The pair keys the operator left ticked on the preview. Every proposed
      # pair renders as a ticked checkbox alongside one blank hidden entry, so
      # the parameter is always present when pairs were shown: an absent key
      # means unticked, never "we didn't ask".
      def ticked_offset_pair_keys
        keys = params[:offset_pair_keys]
        return Set.new unless keys.is_a?(Array)

        keys.map(&:to_s).compact_blank.to_set
      end

      # Attributed rows not claimed by one of the applied pairs, in paste order.
      # Keyed on the pair's row INDEXES, not row equality: two byte-identical
      # rows in one paste are two real transactions, and pairing one must not
      # silently drop the other.
      def entries_outside(entries, pairs)
        consumed = pairs.flat_map { |pair| [ pair.debit_index, pair.credit_index ] }.to_set
        entries.each_with_index.reject { |_entry, index| consumed.include?(index) }.map(&:first)
      end

      # Match debits to Submitted/Paid expenses (each claimed at most once) and
      # credits to income budgets. Returns [matched_debits, matched_credits,
      # unmatched] where matched_* are [attributed entry, expense|budget] pairs.
      #
      # Both matches are SCOPED TO THE ROW'S COST CENTRE. Without that, a
      # termtime debit of the same amount and nominal code could mark a Fringe
      # expense Paid and email its producer "EUSA has paid you" — money attributed
      # to the wrong pot plus a claim that cannot be un-sent. A row that finds no
      # expense in its own cost centre simply lists as unmatched, which a human
      # can see and fix.
      #
      # Expenses already reconciled are excluded so a later or overlapping EUSA
      # export can never re-match, re-pay, or re-email a producer for an expense
      # that's already been paid — the dedup only catches an identical row, so a
      # row that differs slightly would otherwise slip through.
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

      def matchable_statuses
        [ ::Reimbursements::Status::SUBMITTED, ::Reimbursements::Status::PAID ]
      end

      # Every expense a debit row is allowed to match, as a fresh array the
      # caller may consume from (a matched expense is deleted so it can't be
      # claimed twice). Not yet cost-centre scoped — expenses_in does that per
      # row, from this one shared pool, so an expense claimed by any row is out
      # of reach of every other row whatever its cost centre.
      def matchable_expenses
        reconciled_ids = reconciled_expense_ids
        store.expenses.select do |e|
          matchable_statuses.include?(e.status) && !already_reconciled?(e, reconciled_ids)
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

      # Whether a record belonging to +record_cost_centre_id+ is in +cost_centre+.
      #
      # An expense with no budget at all, or a budget with no cost centre, has no
      # cost centre to compare — Budget#cost_centre_id is nullable and predates
      # this scoping. Such a record is treated as belonging to the row's centre
      # ONLY while exactly one cost centre is configured, because then there is
      # nowhere else it could belong and the scoping cannot be wrong. The moment
      # a second centre exists the ambiguity is real, so we stop guessing: the
      # unattributed expense drops out of matching and its rows list as unmatched
      # until someone gives its budget a cost centre. Guessing instead would pay
      # a claim out of the wrong pot and email the producer about it.
      def in_cost_centre?(record_cost_centre_id, cost_centre)
        return record_cost_centre_id == cost_centre.id if record_cost_centre_id

        configured_cost_centres.one?
      end

      # What each proposed pair would do if the operator unticked it, as
      # { pair key => { expense:, budget: } }.
      #
      # The "will mark N matched expenses Paid" count is computed from the
      # UNPAIRED rows only, but apply hands an unticked pair's legs back to the
      # ordinary matching, so it can pay (and email) expenses the confirmation
      # never mentioned. Naming the specific expense per pair is more use than a
      # corrected total: it tells the operator what THIS tick is deciding,
      # before they submit, and stays right however many pairs they untick.
      #
      # Pairs are walked in order, each consuming its match from the pool that
      # the ordinary matching left behind, because apply claims each expense
      # once — two lookalike pairs must not both promise to pay the same one.
      #
      # Each pair's cost centre comes from its legs' entries, so the note only
      # ever names an expense the unticked pair could really pay.
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

      # Record ids of every expense already linked to an imported EUSA actual —
      # the durable, cross-paste signal that an expense has been reconciled.
      def reconciled_expense_ids
        store.eusa_actuals.flat_map(&:linked_expense_ids).to_set
      end

      # An expense counts as already reconciled if an imported actual links to it
      # or a payment has been confirmed against it — either means "already paid",
      # so it must not be matched (and paid + emailed) a second time.
      def already_reconciled?(expense, reconciled_ids)
        reconciled_ids.include?(expense.record_id) || expense.payment_confirmed_date.present?
      end

      # Each row's write sequence is rescued independently, so one row's
      # failure can't abort the whole paste — the rest of the batch still
      # commits, and (critically) notify_paid_producers below still runs for
      # every row that did commit. Without this, an exception on row k used to
      # 500 the whole request before any "you've been paid" email went out,
      # and since apply is idempotent-by-design (already_reconciled? excludes
      # anything already linked), a retry could never re-send those emails —
      # they'd be lost permanently even though rows 1..k-1 were genuinely paid.
      # Returns [committed_pairs, committed_debits, committed_credits,
      # committed_unmatched] — each the subset that actually made it through, so
      # the caller's summary counts (and the producer-notification list) never
      # claim more happened than really did.
      def apply_reconciliation(entries, pairs, matched_debits, matched_credits, unmatched)
        imported_at = Time.current

        committed_pairs = pairs.select { |pair| apply_offsetting_pair(entries, pair, imported_at) }
        committed_debits = matched_debits.select { |entry, expense| apply_debit_row(entry, expense, imported_at) }
        committed_credits = matched_credits.select { |entry, budget| apply_credit_row(entry, budget, imported_at) }
        committed_unmatched = unmatched.select { |entry| apply_unmatched_row(entry, imported_at) }

        [ committed_pairs, committed_debits, committed_credits, committed_unmatched ]
      end

      # Both legs are imported and then pointed at each other: the pair nets to
      # zero, but finance still needs to see that both entries exist. One store
      # call, one transaction — see DatabaseStore#create_offsetting_pair! for why
      # a half-written pair is unrepairable.
      def apply_offsetting_pair(entries, pair, imported_at)
        with_row_rescue("an offsetting pair") do
          store.create_offsetting_pair!(actuals_attrs(entries[pair.debit_index], imported_at),
                                        actuals_attrs(entries[pair.credit_index], imported_at))
        end
      end

      def apply_debit_row(entry, expense, imported_at)
        with_row_rescue("expense ##{expense.auto_number}") do
          actual = store.create_actual!(actuals_attrs(entry, imported_at))
          store.link_actual_to_expense!(actual.record_id, expense.record_id)
          store.update_expense!(expense.record_id, status: ::Reimbursements::Status::PAID,
                                payment_confirmed_date: entry.row.date)
        end
      end

      def apply_credit_row(entry, budget, imported_at)
        with_row_rescue("budget #{budget.name}") do
          actual = store.create_actual!(actuals_attrs(entry, imported_at))
          store.link_actual_to_budget!(actual.record_id, budget.record_id)
        end
      end

      def apply_unmatched_row(entry, imported_at)
        with_row_rescue("an unmatched row") do
          store.create_actual!(actuals_attrs(entry, imported_at))
        end
      end

      # Runs the block, returning true; a raised StandardError is reported and
      # converted to false so one row's failure can't abort the whole paste
      # (see apply_reconciliation's comment above for why this matters).
      def with_row_rescue(subject)
        yield
        true
      rescue StandardError => e
        report_reconciliation_row_failure(subject, e)
        false
      end

      def report_reconciliation_row_failure(subject, error)
        log_and_notify("Reimbursements: reconciliation row failed for #{subject} — #{error.message}", error,
                       context: { source: "reimbursements_reconciliation_apply", subject: subject })
        (@reconciliation_errors ||= []) << "#{subject}: #{error.message}"
      end

      # One "you've been paid" email per producer, covering all of their newly
      # paid expenses. Producers with no linked person or no email are skipped.
      #
      # Sent through Graph (from the cost centre's send mailbox), inline: Apply is
      # already a synchronous, API-heavy operator action. A send failure for one
      # producer is rescued + logged so it never breaks the reconciliation or the
      # remaining producers' emails.
      def notify_paid_producers(matched_debits)
        matched_debits.group_by { |_entry, expense| expense.person }.each do |person, pairs|
          next if person.nil? || person.email.blank?

          expenses = pairs.map { |_entry, expense| expense }
          begin
            notifier.payment_confirmation(
              to: person.email,
              greeting_name: ::Reimbursements::GreetingName.for(person),
              expenses: expenses
            )
          rescue StandardError => e
            log_and_notify("Reimbursements: payment email failed for #{person.email} — #{e.message}", e,
                           context: { source: "reimbursements_payment_email", payee: person.email })
          end
        end
      end

      # The EUSA period (from the row) is the scoping key, so source_month is
      # never written and its column stays blank on new rows.
      #
      # The cost centre is stored as the resolved FK only. The exported code
      # itself is not persisted: it is the *input* to attribution, kept on the
      # parser's ActualsRow for exactly as long as that decision takes, and
      # storing it beside the answer would only let the two disagree.
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
