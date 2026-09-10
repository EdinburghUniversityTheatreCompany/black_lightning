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

      # Enough that the right claim is almost always on the list, few enough
      # that the page stays readable. The list is sorted by closeness, so a
      # claim past this point was never the answer.
      LINK_CANDIDATE_LIMIT = 50

      def index
        @title = "EUSA Actuals"
        # The SELECTED cost centre's rows (all of them when no centre is
        # picked). Not store.eusa_actuals, which stays whole because the
        # reconcile wizard deduplicates and matches against it per row.
        actuals = store.eusa_actuals_for_cost_centre
        @periods = actuals.map(&:period).reject(&:blank?).uniq.sort
        @period = params[:period].to_s.strip
        actuals = actuals.select { |a| a.period == @period } if @period.present?
        # Offsetting rows net to zero against their counterpart, so they are
        # bookkeeping noise: out of the working set unless asked for.
        @offset_count = actuals.count(&:offset?)
        @include_offsets = ActiveModel::Type::Boolean.new.cast(params[:include_offsets]).present?
        actuals = actuals.reject(&:offset?) unless @include_offsets
        # Newest first: imported rows carry an imported_at; fall back to the
        # transaction date so hand-imported/legacy rows still sort sensibly.
        sorted = actuals.sort_by { |a| a.imported_at || a.date&.to_time || Time.zone.at(0) }.reverse
        respond_to do |format|
          format.html { @actuals = paginate(sorted) }
          # Export the FULL filtered set (the period filter carries through the
          # query string) — pagination is display-only, so the CSV isn't paged.
          format.csv { send_export ::Reimbursements::Exports::Actuals, sorted }
        end
      end

      def new_expense
        @title = "Create expense from EUSA actual"
        @budgets = offerable_budgets
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

      private

      # The index's own filters, so undoing an offset doesn't throw the operator
      # back to an unfiltered first page.
      def actuals_path_with_filters
        admin_reimbursements_actuals_path(
          params.permit(:period, :include_offsets).to_h.compact_blank
        )
      end

      def set_convertible_actual
        @actual = find_or_404(:find_actual)
        return if @actual.convertible_to_expense?

        redirect_to admin_reimbursements_actuals_path, alert: not_convertible_reason(@actual)
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

      # Claims this row could plausibly settle, closest amount first so the
      # obvious answer is at the top. Deliberately NOT filtered to the row's
      # nominal code or to a date window: this list exists precisely for the
      # rows the automatic matcher, which applies both of those, already gave up
      # on. Paid claims are excluded — one is already settled.
      def link_candidates(actual)
        target = actual.debit || 0
        store.expenses
             .reject { |expense| expense.status == ::Reimbursements::Status::PAID }
             .sort_by { |expense| [ ((expense.amount || 0) - target).abs, -expense.auto_number.to_i ] }
             .first(LINK_CANDIDATE_LIMIT)
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
