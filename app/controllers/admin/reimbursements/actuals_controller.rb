module Admin
  module Reimbursements
    ##
    # Browser over the imported EUSA Actuals ledger (the rows created by the
    # Reconcile wizard). Finance can scan what's been imported, whether a row is
    # linked to an expense or an income budget, and filter by EUSA period.
    #
    # It also turns an unlinked debit row into a From-EUSA expense: a cost EUSA
    # levied on us directly (a utility, a staff recharge) that no producer ever
    # claimed. Those are created settled (Paid, dated from the ledger row) since
    # the money has already moved, and cross-linked back to the row.
    #
    # Gated by the finance grid permission (`:manage, :reimbursements_finance`).
    class ActualsController < FinanceController
      before_action :set_convertible_actual, only: %i[new_expense create_expense
                                                      link_expense confirm_link]
      before_action :set_apportionable_actual, only: %i[apportion create_apportionment]
      before_action :set_pairable_actual, only: %i[offset_pair confirm_offset]

      # How many empty share rows the split form offers. Five is the case it
      # exists for — a Stripe payout covering a Fringe week's shows — and the
      # form's Stimulus controller adds more, so this is a starting point
      # rather than a cap.
      DEFAULT_SHARE_ROWS = 5

      # Enough that the right claim is almost always on the list, few enough
      # that the page stays readable. The list is sorted by closeness, so a
      # claim past this point was never the answer.
      LINK_CANDIDATE_LIMIT = 50

      # Statuses a manual "Link to claim" must never offer. See
      # #link_candidates for why each one is here.
      EXCLUDED_LINK_STATUSES = [
        ::Reimbursements::Status::PAID,
        ::Reimbursements::Status::DRAFT,
        ::Reimbursements::Status::REJECTED
      ].freeze

      # Which slice of the ledger the page is showing, in the URL as ?state=.
      #
      # NEEDS_ATTENTION IS THE DEFAULT, and that is the point of it: the ledger
      # is read after a reconcile to find what is left to do, and every row
      # already attached to a claim or a budget is inert — it offers no action
      # at all. 17 of the 50 rows on the first page were in that state, so the
      # work was hidden among rows nobody could act on.
      STATE_NEEDS_ATTENTION = "needs_attention".freeze
      STATE_ALL = "all".freeze
      STATES = [ STATE_NEEDS_ATTENTION, STATE_ALL ].freeze

      def index
        @title = "EUSA Actuals"
        # The SELECTED cost centre's rows (all of them when no centre is
        # picked). Not store.eusa_actuals, which stays whole because the
        # reconcile wizard deduplicates and matches against it per row.
        actuals = store.eusa_actuals_for_cost_centre
        # The picker's options come from every row in the centre, before the
        # period filter narrows them — otherwise picking one month leaves it as
        # the only month you can pick. Canonical, so the year sorts in order.
        @periods = actuals.map(&:period).reject(&:blank?).uniq.sort
        @period = params[:period].to_s.strip
        @search = params[:search].to_s.strip
        @state = resolved_state

        actuals = actuals.select { |a| a.period == @period } if @period.present?
        actuals = actuals.select { |a| a.matches_search?(@search) } if @search.present?

        # Counted AFTER period and search and BEFORE the state filter, so the
        # switch between the two views describes the rows the operator is
        # actually looking at rather than the whole ledger.
        @matching_count = actuals.size
        @needs_attention_count = actuals.count(&:needs_attention?)
        @offset_count = actuals.count(&:offset?)

        actuals = apply_state(actuals)
        # Newest first: imported rows carry an imported_at; fall back to the
        # transaction date so hand-imported/legacy rows still sort sensibly.
        sorted = actuals.sort_by { |a| a.imported_at || a.date&.to_time || Time.zone.at(0) }.reverse
        respond_to do |format|
          format.html { @actuals = paginate(sorted) }
          # Export the FULL filtered set (every filter carries through the
          # query string) — pagination is display-only, so the CSV isn't paged.
          format.csv { send_export ::Reimbursements::Exports::Actuals, sorted }
        end
      end

      def new_expense
        @title = "Create expense from EUSA actual"
        @budgets = offerable_budgets
        @budget_groups = budget_groups_for(@actual)
        @form = ::Reimbursements::ExpenseForm.from_actual(@actual)
        @form.budget_record_id = budget_for_nominal_code(@actual.nominal_code)
      end

      def create_expense
        @form = ::Reimbursements::ExpenseForm.from_actual(@actual)
        # The ledger row owns the amount and the type; the operator only says
        # which budget it lands on and tidies the description/reference.
        #
        # The picker's own list is what the budget is checked against (the same
        # rule the producer form uses), so a line deleted OR deactivated between
        # this page loading and the operator submitting comes back as a fixable
        # form error rather than a foreign-key 500 or a claim quietly charged to
        # a retired budget.
        @form.offerable_budget_ids = offerable_budget_ids
        @form.budget_record_id = conversion_params[:budget_record_id]
        @form.description = conversion_params[:description]
        @form.payment_reference = conversion_params[:payment_reference]

        unless @form.valid?
          @title = "Create expense from EUSA actual"
          @budgets = offerable_budgets
          @budget_groups = budget_groups_for(@actual)
          render :new_expense, status: :unprocessable_entity
          return
        end

        # One store call, one transaction: a Paid expense with no back-link would
        # leave the row still offering its "Create expense" button, so the next
        # click would double-count the same EUSA charge.
        expense = store.create_expense_for_actual!(
          @actual.record_id,
          @form.create_attrs(nil).merge(status: ::Reimbursements::Status::PAID,
                                        payment_confirmed_date: @actual.date)
        )
        redirect_to admin_reimbursements_actuals_path,
                    notice: "Expense ##{expense.auto_number} created from this EUSA row and " \
                            "recorded as already paid."
      rescue ::Reimbursements::DatabaseStore::NotConvertibleError
        # The row was converted between this request's check and its write (a
        # double-submitted form, or another operator).
        redirect_to admin_reimbursements_actuals_path,
                    alert: "That row had already been converted to an expense, so nothing was " \
                           "created a second time."
      rescue ::Reimbursements::DatabaseStore::BudgetGoneError
        # And the same race on the budget link: the whole transaction rolled
        # back, so the row is still convertible against another budget.
        redirect_to admin_reimbursements_actuals_path,
                    alert: "That budget was deleted while this page was open, so nothing was " \
                           "created. Pick another budget and try again."
      end

      # Undo a mis-detected offsetting pair. The heuristic proposes pairs and the
      # operator ticks them, but a wrong tick stamps real spend as noise and
      # hides it from the ledger view and every rollup, so the way back must not
      # need a console. Both legs stay on the ledger, they just stop cancelling.
      # Attach this row to a claim the matcher missed, settling it exactly as a
      # reconcile run would. The matcher is deliberately conservative — it
      # prefers leaving a row unmatched to inventing a link — so a human needs a
      # way to finish the job without a console. It is also the backstop under
      # the international window: an international claim's stored amount is only
      # finance's estimate until the payment clears, and a rate that moved far
      # enough lands outside even the widened tolerance.
      def link_expense
        @title = "Link EUSA actual to a claim"
        @candidates = link_candidates(@actual)
        # id -> centre for the candidate list, off the store's memoized reader:
        # a claim resolves its centre through its budget, and reading
        # budget.cost_centre per row would be a query per candidate.
        @cost_centres_by_id = store.cost_centres.index_by(&:id)
      end

      def confirm_link
        expense = store.find_expense(params[:expense_id])
        if expense.nil?
          redirect_to actuals_path_with_filters, alert: "That claim no longer exists."
          return
        end

        store.settle_expense_from_actual!(@actual.record_id, expense.record_id,
                                          payment_date: @actual.date,
                                          gbp_charged: @actual.debit)
        redirect_to actuals_path_with_filters,
                    notice: "Linked to ##{expense.auto_number}, which is now Paid" \
                            "#{' with the amount corrected to what EUSA charged' if expense.international?}."
      end

      # Split one credit row across several income budgets. Stripe pays out one
      # lump covering a week of shows, and the ledger row can only carry one
      # budget_id, so without this the whole payout lands on one line.
      def apportion
        @title = "Split an EUSA credit across budgets"
        @budgets = splittable_budgets
        @shares = blank_shares
      end

      def create_apportionment
        @budgets = splittable_budgets
        @shares = submitted_shares

        if (error = apportionment_error)
          @title = "Split an EUSA credit across budgets"
          flash.now[:alert] = error
          render :apportion, status: :unprocessable_entity
          return
        end

        store.apportion_actual!(@actual.record_id, @shares)
        redirect_to actuals_path_with_filters,
                    notice: "Split across #{@shares.length} budgets. Each one now counts its own " \
                            "share of this credit."
      rescue ::Reimbursements::DatabaseStore::NotApportionableError
        # Split between this request's check and its write — a double-submitted
        # form, or another operator. Splitting twice would double the income.
        redirect_to actuals_path_with_filters,
                    alert: "That row had already been split, so nothing was written a second time."
      rescue ::Reimbursements::DatabaseStore::ApportionmentMismatchError
        # Belt and braces under #apportionment_error: the row's own figure
        # cannot change under us, but refusing beats writing a short split.
        redirect_to actuals_path_with_filters,
                    alert: "Those shares did not add up to the row, so nothing was written."
      end

      # Undo a split. The row goes back to unlinked and reappears on the
      # overview's unattributed card, so income nobody has attributed is
      # visible again rather than silently gone.
      def remove_apportionment
        actual = find_or_404(:find_actual)
        unless actual.apportioned?
          redirect_to actuals_path_with_filters, alert: "That row is not split across budgets."
          return
        end

        store.remove_apportionment!(actual.record_id)
        redirect_to actuals_path_with_filters,
                    notice: "That row is an unlinked credit again, and is back on the " \
                            "unattributed list until it is placed."
      end

      # Pair this row with another as an accrual and its reversal, by hand.
      #
      # "Not offsetting" was one-way: it returns both legs to ordinary rows and
      # nothing put them back, so an operator who undid a pair to look at it —
      # or who wants to record a pair the detector's score missed — had no way
      # forward but a console.
      def offset_pair
        @title = "Mark an EUSA row as offsetting"
        @candidates = @actual.offset_candidates(store.eusa_actuals_for_cost_centre)
      end

      def confirm_offset
        counterpart = store.find_actual(params[:counterpart_id])
        # Re-checked here, not just when the page was drawn: the picker is a
        # read that goes stale, and pairing a row that has since been linked to
        # a claim would hide real spend AND leave that claim reading Paid with
        # nothing behind it.
        unless counterpart && @actual.offset_candidates([ counterpart ]).any?
          redirect_to actuals_path_with_filters,
                      alert: "That row can no longer be paired with this one. It may have been " \
                             "linked or paired since this page was opened; check the ledger and " \
                             "try again."
          return
        end

        store.link_offsetting_pair!(@actual.record_id, counterpart.record_id)
        redirect_to actuals_path_with_filters,
                    notice: "Those two rows now cancel each other out, so neither counts as spend " \
                            "or income. Both stay on the ledger, and \"Not offsetting\" undoes it."
      end

      def unoffset
        actual = find_or_404(:find_actual)
        unless actual.offset?
          redirect_to actuals_path_with_filters, alert: "That row is not marked as offsetting."
          return
        end

        store.unlink_offsetting_pair!(actual.record_id)
        redirect_to actuals_path_with_filters,
                    notice: "Both rows of that pair are ordinary ledger rows again, so they count " \
                            "as real spend or income."
      end

      # Detach a row from the claim or the income line it was matched to.
      #
      # A wrong match had no way back short of a console. It also had a second
      # cost the screen never explained: #apportionable? refuses a row that
      # already carries a budget, so a box-office settlement Reconcile attached
      # whole to one income line could never be split across the shows it
      # covered — the one control built for that case never appeared on the one
      # row it was built for.
      #
      # Deletes nothing; the row stays on the ledger and returns to the
      # unattributed card, so money nobody has placed is visible again rather
      # than silently gone. Which link it carries decides what is undone, since
      # the two are undone differently (see the store's two methods).
      def unlink
        actual = find_or_404(:find_actual)

        if actual.linked_expense_ids.any?
          unlink_from_claim(actual)
        elsif actual.linked_budget_ids.any?
          store.unlink_actual_from_budget!(actual.record_id)
          redirect_to actuals_path_with_filters,
                      notice: "Unlinked from that income line. The row is unplaced again, and can " \
                              "now be split across budgets or linked to another line."
        else
          redirect_to actuals_path_with_filters, alert: "That row isn't linked to anything."
        end
      end

      private

      # Unlinking a row from a CLAIM also reverses the settlement it wrote — so
      # the notice says so, rather than leaving the operator to discover that
      # the claim moved back to Submitted.
      def unlink_from_claim(actual)
        store.unlink_actual_from_expense!(actual.record_id)
        redirect_to actuals_path_with_filters,
                    notice: "Unlinked from that claim. If the claim was marked Paid by this row " \
                            "it is back to Submitted, so it will be reconciled again when the " \
                            "right row turns up."
      rescue ::Reimbursements::DatabaseStore::ClaimFromRowError
        redirect_to actuals_path_with_filters,
                    alert: "That claim was created FROM this row, so there is nothing to unlink it " \
                           "back to: the claim only exists because of it. Delete the claim instead, " \
                           "and the row goes back to offering \"Create expense\"."
      end

      # The state the URL asks for, defaulting to the leftovers.
      #
      # ?include_offsets=1 WITHOUT a state means the full ledger, because an
      # offsetting leg is never a row needing attention: asking for the offsets
      # and being given a view that by definition holds none of them would be
      # the control lying. It also keeps every link and bookmark written before
      # the state filter existed pointing at what it used to show.
      def resolved_state
        return params[:state] if STATES.include?(params[:state])
        return STATE_ALL if ActiveModel::Type::Boolean.new.cast(params[:include_offsets]).present?

        STATE_NEEDS_ATTENTION
      end

      # The rows the chosen state leaves on screen.
      #
      # "Show offsetting rows" only applies to the FULL ledger: an offsetting
      # leg nets to zero against its counterpart, so it is never something that
      # needs attention, and a tickbox that could only ever add nothing would
      # be a control that lies. The needs-attention view instead LINKS to the
      # full ledger with the offsets shown (see the index view), which is also
      # the only place a mistaken pairing can be undone.
      def apply_state(actuals)
        if @state == STATE_NEEDS_ATTENTION
          @include_offsets = false
          return actuals.select(&:needs_attention?)
        end

        @include_offsets = ActiveModel::Type::Boolean.new.cast(params[:include_offsets]).present?
        @include_offsets ? actuals : actuals.reject(&:offset?)
      end

      # The index's own filters, so undoing an offset doesn't throw the operator
      # back to an unfiltered first page.
      def actuals_path_with_filters
        admin_reimbursements_actuals_path(
          params.permit(:period, :include_offsets, :state, :search).to_h.compact_blank
        )
      end

      # A row that can be half of a hand-made offsetting pair. Anything else is
      # bounced with the reason, the shape #set_convertible_actual uses.
      def set_pairable_actual
        @actual = find_or_404(:find_actual)
        return if @actual.pairable?

        redirect_to actuals_path_with_filters, alert: not_pairable_reason(@actual)
      end

      def not_pairable_reason(actual)
        return "That row is already part of an offsetting pair." if actual.offset?
        return "That row is split across budgets, so unpick the split first." if actual.apportioned?
        if actual.linked_expense_ids.any? || actual.linked_budget_ids.any?
          return "That row is linked to a claim or a budget. Unlink it first: marking it " \
                 "offsetting would hide spend that a claim or a line is still counting."
        end

        "That row has no debit or credit, so there is nothing for another row to cancel out."
      end

      def set_convertible_actual
        @actual = find_or_404(:find_actual)
        return if @actual.convertible_to_expense?

        redirect_to admin_reimbursements_actuals_path, alert: not_convertible_reason(@actual)
      end

      def set_apportionable_actual
        @actual = find_or_404(:find_actual)
        return if @actual.apportionable?

        redirect_to admin_reimbursements_actuals_path, alert: not_apportionable_reason(@actual)
      end

      def not_apportionable_reason(actual)
        if actual.offset?
          "That row offsets another one, so together they net to zero. Splitting it would " \
            "invent income that never arrived."
        elsif actual.apportioned?
          "That row is already split across budgets. Remove the split first to change it."
        elsif actual.linked_expense_ids.any? || actual.linked_budget_ids.any?
          "That row is already attached to a claim or a budget, so splitting it as well would " \
            "count its money twice."
        else
          "Only a credit row can be split across income budgets. A debit is spend: split one by " \
            "creating an expense per share instead."
        end
      end

      # The income lines this row's shares may land on.
      #
      # UNSCOPED, for the reason store.budgets is: an EUSA credit arriving in
      # the tail of one financial year routinely belongs to the income line of
      # the year it was raised in, and the Actuals screens are not year-scoped
      # at all — a picker following the selected year would silently refuse the
      # only line that row could correctly land on. Inactive lines are left out
      # for the reason active_budgets leaves them out: charging a retired line
      # is quiet and wrong.
      #
      # Memoized, so the list the post is VALIDATED against is the list the
      # page RENDERED — the rule ExpenseForm#offerable_budget_ids follows.
      def splittable_budgets
        @splittable_budgets ||= store.budgets.select { |b| b.active && b.income? }
                                     .sort_by(&:display_name)
      end

      def splittable_budget_ids
        splittable_budgets.map(&:record_id)
      end

      def blank_shares
        Array.new(DEFAULT_SHARE_ROWS) { { budget_id: nil, amount: nil, amount_typed: "" } }
      end

      # The typed rows, blanks dropped. A row is blank when it names no budget
      # AND no amount — a half-filled row is a mistake worth reporting, not
      # something to silently ignore.
      #
      # +amount_typed+ is kept beside the parsed figure so a refused submit
      # re-renders what the operator actually typed rather than blanking it.
      # An unreadable amount parses to nil and is caught by
      # #apportionment_error; it is never handed on raw, because AR casts a
      # string to a decimal column with #to_d and "£1,200" would store 0.
      def submitted_shares
        (params[:shares] || {}).values.filter_map do |row|
          typed = row[:amount].to_s
          budget_id = row[:budget_id].to_s
          next if typed.strip.blank? && budget_id.blank?

          { budget_id: budget_id.presence, amount: ::Reimbursements::AmountParser.parse(typed),
            amount_typed: typed }
        end
      end

      def apportionment_error
        return "Add at least one budget and amount to split this row across." if @shares.empty?

        share_rule_error || total_rule_error
      end

      def share_rule_error
        return "Every share needs a budget and a readable amount, like 2500 or £2,500." if
          @shares.any? { |s| s[:budget_id].blank? || s[:amount].nil? || !s[:amount].positive? }

        ids = @shares.map { |s| s[:budget_id] }
        # The picker is drawn from one list and the write goes straight to
        # budget_id, so an id the page never offered — a line deleted,
        # retired, or typed in by hand — has to be refused here.
        return "One of those budgets is no longer available. Reload the page and pick again." if
          (ids - splittable_budget_ids).any?

        "A budget can only take one share of a row. Add its shares together instead." if
          ids.uniq.length != ids.length
      end

      def total_rule_error
        total = @shares.sum { |s| s[:amount] }
        return nil if total == @actual.apportionable_total

        "The shares add up to #{helpers.reimbursements_money(total)}, but this row is " \
          "#{helpers.reimbursements_money(@actual.apportionable_total)}. " \
          "Apportioning divides the row, so the parts have to add up to it exactly."
      end

      def not_convertible_reason(actual)
        if actual.offset?
          "That row offsets another one, so together they net to zero. It isn't real spend and " \
            "can't become an expense."
        elsif actual.linked_expense_ids.any?
          "That row is already linked to an expense, so converting it again would double-count it."
        else
          "Only a debit row can become an expense: a credit is income, and belongs to a budget."
        end
      end

      # Claims this row could plausibly settle. Deliberately NOT filtered to
      # the row's nominal code or to a date window: this list exists precisely
      # for the rows the automatic matcher, which applies both of those,
      # already gave up on.
      #
      # WHICH STATUSES. Paid is out — already settled. DRAFT and REJECTED are
      # out too, and that is the point of this: a draft is a claim its
      # submitter has not finished writing, and a rejected one is a claim
      # finance refused, so settling either marks paid something nobody agreed
      # to pay. The unfiltered list put a Rejected claim third. What is left —
      # Pending, Approved, Submitted — can each legitimately have been paid:
      # Submitted is the matcher's own set, and a claim settled outside a batch
      # (an imported claim, a payment EUSA made directly) can still be sitting
      # at either of the other two.
      def link_candidates(actual)
        store.expenses
             .reject { |expense| EXCLUDED_LINK_STATUSES.include?(expense.status) }
             .sort_by { |expense| link_candidate_rank(expense, actual) }
             .first(LINK_CANDIDATE_LIMIT)
      end

      # A claim whose payee is NAMED IN THE ROW'S NARRATIVE comes first,
      # whatever the amounts say.
      #
      # The narrative is routinely "BACS PAYMENT KIRSTY TOLMIE" — the strongest
      # evidence on the row and the very thing a human reads it for — while
      # amount-closeness alone ranked her claim sixth behind four unrelated
      # claims that happened to be nearer. Amount-closeness stays the
      # tie-break, then the newest claim.
      def link_candidate_rank(expense, actual)
        target = actual.debit || 0
        [ named_in_narrative?(expense, actual) ? 0 : 1,
          ((expense.amount || 0) - target).abs,
          -expense.auto_number.to_i ]
      end

      # Whether any word of the payee's or the submitter's name appears in the
      # narrative. Word by word, because the ledger abbreviates and reorders
      # ("TOLMIE K", "K TOLMIE"), and only words of 3+ characters, so an
      # initial or a stray "DE" cannot match half the ledger.
      def named_in_narrative?(expense, actual)
        narrative = "#{actual.narrative} #{actual.narrative_1}".downcase
        return false if narrative.blank?

        names = [ expense.effective_payee_name, expense.person&.name ].compact_blank
        names.flat_map { |name| name.downcase.split(/[^a-z]+/) }
             .select { |word| word.length >= 3 }
             .any? { |word| narrative.include?(word) }
      end

      def conversion_params
        params.require(:reimbursements_expense_form)
              .permit(:budget_record_id, :description, :payment_reference)
      end

      # The budgets this page's picker offers, memoized so the list the form is
      # validated against is the list it displays — see the producer
      # ExpensesController's reader of the same name.
      def offerable_budgets
        @budgets ||= store.active_budgets
      end

      def offerable_budget_ids
        offerable_budgets.map(&:record_id)
      end

      # The budget picker as two labelled groups: the lines on the row's own
      # nominal code first, then everything else.
      #
      # The nominal code is the strongest hint the row carries and the picker
      # ignored it entirely, listing all 34 budgets alphabetically — with eight
      # of them sharing one code, finding the right line meant knowing it
      # already. Every line stays offerable (a code is a hint, not a rule, and
      # the operator may genuinely be charging this elsewhere), so this is an
      # ORDER, not a filter; the label on each group says which is which.
      #
      # Each option also prints its nominal code, so the grouping can be
      # checked rather than trusted.
      def budget_groups_for(actual)
        matching, others = offerable_budgets.partition do |budget|
          actual.nominal_code.present? && budget.nominal_code == actual.nominal_code
        end
        groups = []
        if matching.any?
          groups << [ "Matches this row's nominal code (#{actual.nominal_code})",
                      budget_options(matching) ]
        end
        groups << [ matching.any? ? "Every other budget" : "Budgets", budget_options(others) ]
        groups
      end

      def budget_options(budgets)
        budgets.map { |budget| [ "#{budget.picker_label} · #{budget.nominal_code}", budget.record_id ] }
      end

      # The budget a nominal code unambiguously belongs to, so the operator
      # doesn't retype what the code already says. Left blank when several
      # budgets share the code — guessing between them would be worse than
      # asking.
      def budget_for_nominal_code(nominal_code)
        return nil if nominal_code.blank?

        matching = offerable_budgets.select { |budget| budget.nominal_code == nominal_code }
        matching.sole.record_id if matching.one?
      end
    end
  end
end
