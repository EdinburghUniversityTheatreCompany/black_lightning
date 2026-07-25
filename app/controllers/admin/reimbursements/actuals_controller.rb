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
      before_action :set_convertible_actual, only: %i[new_expense create_expense]

      def index
        @title = "EUSA Actuals"
        actuals = store.eusa_actuals
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
        @budgets = store.active_budgets
        @form = ::Reimbursements::ExpenseForm.from_actual(@actual)
        @form.budget_record_id = budget_for_nominal_code(@actual.nominal_code)
      end

      def create_expense
        @form = ::Reimbursements::ExpenseForm.from_actual(@actual)
        # The ledger row owns the amount and the type; the operator only says
        # which budget it lands on and tidies the description/reference.
        @form.budget_record_id = conversion_params[:budget_record_id]
        @form.description = conversion_params[:description]
        @form.payment_reference = conversion_params[:payment_reference]

        unless conversion_valid?
          @title = "Create expense from EUSA actual"
          @budgets = store.active_budgets
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
      end

      private

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

      def conversion_params
        params.require(:reimbursements_expense_form)
              .permit(:budget_record_id, :description, :payment_reference)
      end

      def conversion_valid?
        valid = @form.valid?
        error = budget_record_id_error(@form.budget_record_id)
        return valid if error.nil?

        @form.errors.add(:budget_record_id, error)
        false
      end

      # The budget a nominal code unambiguously belongs to, so the operator
      # doesn't retype what the code already says. Left blank when several
      # budgets share the code — guessing between them would be worse than
      # asking.
      def budget_for_nominal_code(nominal_code)
        return nil if nominal_code.blank?

        matching = store.active_budgets.select { |budget| budget.nominal_code == nominal_code }
        matching.sole.record_id if matching.one?
      end
    end
  end
end
