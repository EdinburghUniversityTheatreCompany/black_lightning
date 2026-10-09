module Admin
  module Reimbursements
    ##
    # Browser over the imported EUSA actuals ledger, plus the hand fixes for rows Reconcile left
    # over: convert a debit to a From-EUSA expense, link to a claim, split a credit, pair or unpair
    # offsetting legs, unlink. Finance only.
    class ActualsController < FinanceController
      before_action :set_convertible_actual, only: %i[new_expense create_expense
                                                      link_expense confirm_link]
      before_action :set_apportionable_actual, only: %i[apportion create_apportionment]
      before_action :set_pairable_actual, only: %i[offset_pair confirm_offset]

      # Five covers a Stripe payout for a Fringe week's shows; the form's Stimulus controller adds more.
      DEFAULT_SHARE_ROWS = 5

      # The list is sorted by closeness, so a claim past this was never the answer.
      LINK_CANDIDATE_LIMIT = 50

      # Statuses a manual "Link to claim" must never offer or settle; see #link_candidates.
      EXCLUDED_LINK_STATUSES = [
        ::Reimbursements::Status::PAID,
        ::Reimbursements::Status::DRAFT,
        ::Reimbursements::Status::REJECTED
      ].freeze

      # Which slice of the ledger is showing, as ?state=. Needs-attention is the default: after a
      # reconcile the work is the leftovers, and rows already on a claim or budget offer no action.
      STATE_NEEDS_ATTENTION = "needs_attention".freeze
      STATE_ALL = "all".freeze
      STATES = [ STATE_NEEDS_ATTENTION, STATE_ALL ].freeze

      def index
        @title = "EUSA Actuals"
        # Not store.eusa_actuals: reconcile dedups and matches against the whole list.
        actuals = store.eusa_actuals_for_cost_centre
        # Taken before the period filter, or picking one month leaves it the only month to pick.
        @periods = actuals.map(&:period).reject(&:blank?).uniq.sort
        @period = params[:period].to_s.strip
        @search = params[:search].to_s.strip
        resolve_state

        actuals = actuals.select { |a| a.period == @period } if @period.present?
        actuals = actuals.select { |a| a.matches_search?(@search) } if @search.present?

        # After period and search, before the state filter, so the view switch describes the rows
        # being looked at rather than the whole ledger.
        @matching_count = actuals.size
        @needs_attention_count = actuals.count(&:needs_attention?)
        @offset_count = actuals.count(&:offset?)

        actuals = apply_state(actuals)
        sorted = actuals.sort_by { |a| a.imported_at || a.date&.to_time || Time.zone.at(0) }.reverse
        respond_to do |format|
          format.html { @actuals = paginate(sorted) }
          # The CSV is the full filtered set; pagination is display-only.
          format.csv { send_export ::Reimbursements::Exports::Actuals, sorted }
        end
      end

      def new_expense
        prepare_expense_page
        @form = ::Reimbursements::ExpenseForm.from_actual(@actual)
        @form.budget_record_id = budget_for_nominal_code(@actual.nominal_code)
      end

      def create_expense
        @form = ::Reimbursements::ExpenseForm.from_actual(@actual)
        # The ledger row owns the amount and type. The budget is checked against the picker's own
        # list, so a line deleted or deactivated since the page loaded is a form error, not an FK
        # 500 or a charge to a retired budget.
        @form.offerable_budget_ids = offerable_budgets.map(&:record_id)
        @form.budget_record_id = conversion_params[:budget_record_id]
        @form.description = conversion_params[:description]
        @form.payment_reference = conversion_params[:payment_reference]

        unless @form.valid?
          prepare_expense_page
          render :new_expense, status: :unprocessable_entity
          return
        end

        # One store call, one transaction: a Paid expense without its back-link leaves the row
        # offering "Create expense" again, which double-counts the charge.
        expense = store.create_expense_for_actual!(
          @actual.record_id,
          # submitted_at takes the ledger date too, or before_create stamps the click date.
          @form.create_attrs(nil).merge(status: ::Reimbursements::Status::PAID,
                                        payment_confirmed_date: @actual.date,
                                        submitted_at: @actual.date&.beginning_of_day)
        )
        redirect_to actuals_path_with_filters,
                    notice: "Expense ##{expense.auto_number} created from this EUSA row and " \
                            "recorded as already paid."
      rescue ::Reimbursements::DatabaseStore::NotConvertibleError
        # Converted between this request's check and its write (double submit, or another operator).
        redirect_to actuals_path_with_filters,
                    alert: "That row had already been converted to an expense, so nothing was " \
                           "created a second time."
      rescue ::Reimbursements::DatabaseStore::BudgetGoneError
        # The same race on the budget; the transaction rolled back, so the row is still convertible.
        redirect_to actuals_path_with_filters,
                    alert: "That budget was deleted while this page was open, so nothing was " \
                           "created. Pick another budget and try again."
      end

      # Attach this row to a claim the matcher missed, settling it as a reconcile run would. Also the
      # backstop under the international window, for a rate that moved further than that tolerates.
      def link_expense
        @title = "Link EUSA actual to a claim"
        @candidates = link_candidates(@actual)
        # Off the store's memoized reader: budget.cost_centre per candidate would be a query each.
        @cost_centres_by_id = store.cost_centres.index_by(&:id)
      end

      def confirm_link
        expense = store.find_expense(params[:expense_id])
        if expense.nil?
          redirect_to actuals_path_with_filters, alert: "That claim no longer exists."
          return
        end
        # Re-checked on the write: #link_candidates was a stale read.
        return refuse_settle(expense.status) if EXCLUDED_LINK_STATUSES.include?(expense.status)

        store.settle_expense_from_actual!(@actual.record_id, expense.record_id,
                                          payment_date: @actual.date,
                                          gbp_charged: @actual.debit)
        redirect_to actuals_path_with_filters,
                    notice: "Linked to ##{expense.auto_number}, which is now Paid" \
                            "#{' with the amount corrected to what EUSA charged' if expense.international?}."
      rescue ::Reimbursements::DatabaseStore::NotSettleableError => e
        # The claim changed between the check above and the store's locked re-read.
        refuse_settle(e.status)
      end

      # Split one credit across several income budgets: a ledger row carries one budget_id, so a
      # Stripe payout covering a week of shows would otherwise land on one line.
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
        # Split between this request's check and its write; a second split would double the income.
        redirect_to actuals_path_with_filters,
                    alert: "That row had already been split, so nothing was written a second time."
      rescue ::Reimbursements::DatabaseStore::ApportionmentMismatchError
        # Backstop under #apportionment_error: refuse rather than write a short split.
        redirect_to actuals_path_with_filters,
                    alert: "Those shares did not add up to the row, so nothing was written."
      end

      # Undo a split. The row returns to the overview's unattributed card, so the income is visible
      # again rather than silently gone.
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

      # Pair this row with another as accrual and reversal by hand, for a pair the detector missed.
      def offset_pair
        @title = "Mark an EUSA row as offsetting"
        @candidates = @actual.offset_candidates(store.eusa_actuals_for_cost_centre)
      end

      def confirm_offset
        counterpart = store.find_actual(params[:counterpart_id])
        # Re-checked on the write: the picker is a stale read, and pairing a row since linked to a
        # claim would hide real spend and leave that claim Paid with nothing behind it.
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

      # Undo a mis-detected offsetting pair; both legs stay on the ledger.
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

      # Detach a row from the claim or income line it was matched to. Nothing is deleted: the row
      # returns to the unattributed card. It is also how a settlement Reconcile attached whole to
      # one income line becomes splittable, since #apportionable? refuses a row that carries a budget.
      def unlink
        actual = find_or_404(:find_actual)

        if actual.expense_id?
          unlink_from_claim(actual)
        elsif actual.budget_id?
          store.unlink_actual_from_budget!(actual.record_id)
          redirect_to actuals_path_with_filters,
                      notice: "Unlinked from that income line. The row is unplaced again, and can " \
                              "now be split across budgets or linked to another line."
        else
          redirect_to actuals_path_with_filters, alert: "That row isn't linked to anything."
        end
      end

      private

      # Also reverses the settlement the row wrote, and the notice says so.
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

      # ?include_offsets=1 without a state means the full ledger: an offset leg never needs
      # attention, so the default view would hold none of what was asked for.
      def resolve_state
        include_offsets = ActiveModel::Type::Boolean.new.cast(params[:include_offsets]) || false
        default_state = include_offsets ? STATE_ALL : STATE_NEEDS_ATTENTION
        @state = STATES.include?(params[:state]) ? params[:state] : default_state
        # Show offsetting rows applies only to the full ledger.
        @include_offsets = include_offsets && @state == STATE_ALL
      end

      def apply_state(actuals)
        return actuals.select(&:needs_attention?) if @state == STATE_NEEDS_ATTENTION

        @include_offsets ? actuals : actuals.reject(&:offset?)
      end

      # The index's own filters and cost centre, so an action taken from a filtered list (or a page
      # reached from one) comes back to that list. scope_params goes after compact_blank, which would
      # drop an explicit All.
      def actual_filters
        params.permit(:period, :include_offsets, :state, :search).to_h.compact_blank.merge(scope_params)
      end
      helper_method :actual_filters

      def actuals_path_with_filters
        admin_reimbursements_actuals_path(actual_filters)
      end
      helper_method :actuals_path_with_filters

      def set_pairable_actual
        @actual = find_or_404(:find_actual)
        return if @actual.pairable?

        redirect_to actuals_path_with_filters, alert: not_pairable_reason(@actual)
      end

      def not_pairable_reason(actual)
        return "That row is already part of an offsetting pair." if actual.offset?
        return "That row is split across budgets, so unpick the split first." if actual.apportioned?
        if actual.expense_id? || actual.budget_id?
          return "That row is linked to a claim or a budget. Unlink it first: marking it " \
                 "offsetting would hide spend that a claim or a line is still counting."
        end

        "That row has no debit or credit, so there is nothing for another row to cancel out."
      end

      def set_convertible_actual
        @actual = find_or_404(:find_actual)
        return if @actual.convertible_to_expense?

        redirect_to actuals_path_with_filters, alert: not_convertible_reason(@actual)
      end

      def set_apportionable_actual
        @actual = find_or_404(:find_actual)
        return if @actual.apportionable?

        redirect_to actuals_path_with_filters, alert: not_apportionable_reason(@actual)
      end

      def not_apportionable_reason(actual)
        if actual.offset?
          "That row offsets another one, so together they net to zero. Splitting it would " \
            "invent income that never arrived."
        elsif actual.apportioned?
          "That row is already split across budgets. Remove the split first to change it."
        elsif actual.expense_id? || actual.budget_id?
          "That row is already attached to a claim or a budget, so splitting it as well would " \
            "count its money twice."
        else
          "Only a credit row can be split across income budgets. A debit is spend: split one by " \
            "creating an expense per share instead."
        end
      end

      # The income lines this row's shares may land on. UNSCOPED like store.budgets: a credit from
      # the tail of one financial year belongs to that year's income line, and these screens are not
      # year-scoped. Inactive lines are left out. Memoized like #offerable_budgets, so the list
      # validated is the list rendered.
      def splittable_budgets
        @splittable_budgets ||= store.budgets.select { |b| b.active && b.income? }
                                     .sort_by(&:display_name)
      end

      def blank_shares
        Array.new(DEFAULT_SHARE_ROWS) { { budget_id: nil, amount: nil, amount_typed: "" } }
      end

      # The typed rows, blanks dropped. A row is blank when it names no budget AND no amount; a
      # half-filled row is a mistake to report. amount_typed is kept so a refused submit re-renders
      # what was typed. An unreadable amount parses to nil and is never handed on raw: AR casts
      # "£1,200" to 0.
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
        # The write goes straight to budget_id, so an id the page never offered (deleted, retired,
        # typed by hand) has to be refused here.
        return "One of those budgets is no longer available. Reload the page and pick again." if
          (ids - splittable_budgets.map(&:record_id)).any?

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
        elsif actual.expense_id?
          "That row is already linked to an expense, so converting it again would double-count it."
        else
          "Only a debit row can become an expense: a credit is income, and belongs to a budget."
        end
      end

      # Claims this row could settle. Not filtered by nominal code or date: the automatic matcher
      # applies both, and this list is for the rows it gave up on. Paid is out (already settled).
      # Draft and Rejected are out because settling one marks paid something nobody agreed to pay.
      # Pending, Approved and Submitted can each have been paid outside a batch.
      def link_candidates(actual)
        store.expenses
             .reject { |expense| EXCLUDED_LINK_STATUSES.include?(expense.status) }
             .sort_by { |expense| link_candidate_rank(expense, actual) }
             .first(LINK_CANDIDATE_LIMIT)
      end

      def refuse_settle(status)
        redirect_to actuals_path_with_filters,
                    alert: "That claim is #{status} now, so this row can't settle it."
      end

      # A claim whose payee is named in the narrative ("BACS PAYMENT A SMITH") comes first, whatever
      # the amounts say; then amount closeness, then the newest claim.
      def link_candidate_rank(expense, actual)
        target = actual.debit || 0
        [ named_in_narrative?(expense, actual) ? 0 : 1,
          ((expense.amount || 0) - target).abs,
          -expense.auto_number.to_i ]
      end

      # Word by word, because the ledger abbreviates and reorders ("SMITH A"), and only words of 3+
      # characters, so an initial cannot match half the ledger.
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

      # Memoized so the list the form is validated against is the list it displays.
      def offerable_budgets
        @offerable_budgets ||= store.active_budgets
      end

      def prepare_expense_page
        @title = "Create expense from EUSA actual"
        @budget_groups = budget_groups_for(@actual)
      end

      # The lines on the row's nominal code first, then every other line grouped by area as the
      # producer's picker is. An ORDER, not a filter: the code is a hint, and the operator may be
      # charging this elsewhere. Each option prints its nominal code so the grouping can be checked.
      def budget_groups_for(actual)
        matching, others = offerable_budgets.partition do |budget|
          actual.nominal_code.present? && budget.nominal_code == actual.nominal_code
        end
        groups = ::Reimbursements::Budget.picker_groups(others) { |budget| budget_option_label(budget) }
        return groups if matching.empty?

        groups.unshift([ "Matches this row's nominal code (#{actual.nominal_code})",
                         matching.map { |budget| [ budget_option_label(budget), budget.record_id ] } ])
      end

      def budget_option_label(budget) = "#{budget.picker_label} · #{budget.nominal_code}"

      # The budget a nominal code unambiguously names; blank when several share it, since guessing
      # is worse than asking.
      def budget_for_nominal_code(nominal_code)
        return nil if nominal_code.blank?

        matching = offerable_budgets.select { |budget| budget.nominal_code == nominal_code }
        matching.sole.record_id if matching.one?
      end
    end
  end
end
