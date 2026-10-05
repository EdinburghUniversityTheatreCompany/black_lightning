module Admin
  module Reimbursements
    ##
    # A producer's own expenses: list, submission (or draft), and editing while
    # still a draft or pending.
    class ExpensesController < BaseController
      rescue_from ExpenseNoLongerEditable, with: :expense_no_longer_editable

      def index
        if params[:refresh].present?
          store.refresh_expenses!
          redirect_to admin_reimbursements_expenses_path and return
        end

        @title = "My Claims"
        @expenses = current_person ? store.expenses_for(current_person.record_id) : []
      end

      def new
        @title = "New Expense"
        @form = ::Reimbursements::ExpenseForm.new
        @budgets = offerable_budgets
      end

      def create
        @form = ::Reimbursements::ExpenseForm.new(
          expense_form_params.merge(offerable_budget_ids: offerable_budget_ids)
        )
        return render_form(:new, "New Expense") unless @form.valid?

        person = person_link.ensure_person!(current_user)
        expense = store.create_expense!(@form.create_attrs(person.record_id))
        redirect_with_attachment_result(expense.record_id, created_notice)
      rescue ::Reimbursements::DatabaseStore::BudgetGoneError
        # The budget went between the form-level check and the insert.
        budget_gone_error
        render_form(:new, "New Expense")
      end

      # Read-only view of the submitter's own claim at any status.
      def show
        @expense = find_own_expense!(params[:id])
        @title = "Expense ##{@expense.auto_number}"
      end

      def edit
        @expense = find_own_editable_expense!(params[:id])
        @title = "Edit Expense"
        @form = ::Reimbursements::ExpenseForm.from_expense(@expense)
        @budgets = offerable_budgets
      end

      def update
        @expense = find_own_editable_expense!(params[:id])
        # Receipts are managed in the gallery on edit.
        @form = ::Reimbursements::ExpenseForm.new(
          expense_form_params.merge(require_receipts: false,
                                    expense_receipt_count: @expense.receipts.size,
                                    offerable_budget_ids: offerable_budget_ids)
        )
        return render_form(:edit, "Edit Expense") unless @form.valid?

        store.update_expense!(@expense.record_id, @form.update_attrs)
        notice = @form.draft? ? "Draft saved." : "Expense updated."
        redirect_with_attachment_result(@expense.record_id, "#{notice}#{dropped_budget_note}")
      rescue ::Reimbursements::DatabaseStore::BudgetGoneError
        budget_gone_error
        render_form(:edit, "Edit Expense")
      end

      # Only a Draft is deleted; a Pending claim is withdrawn from its edit form.
      def destroy
        @expense = find_own_editable_expense!(params[:id])
        unless @expense.status == ::Reimbursements::Status::DRAFT
          redirect_to admin_reimbursements_expenses_path,
                      alert: "Only a draft can be deleted. Withdraw a submitted claim from its edit page instead."
          return
        end

        store.delete_expense!(@expense.record_id)
        redirect_to admin_reimbursements_expenses_path, notice: "Draft deleted."
      end

      private

      # A stale Edit link for a claim finance has since picked up. A warning,
      # not an alert, so it renders as a notice rather than the red error modal.
      def expense_no_longer_editable
        redirect_to admin_reimbursements_expenses_path,
                    flash: { warning: "That claim is now with the finance team and can't be edited. " \
                                      "You can still view it from your expenses list." }
      end

      # Memoized so the list the form is validated against and the list it
      # renders are one read.
      def offerable_budgets
        @budgets ||= store.active_budgets
      end

      def offerable_budget_ids
        offerable_budgets.map(&:record_id)
      end

      # Every failure path renders the form back, so the typing survives.
      def render_form(template, title)
        @title = title
        @budgets = offerable_budgets
        render template, status: :unprocessable_entity
      end

      def budget_gone_error
        @form.errors.add(:budget_record_id, "is no longer available: the finance team removed " \
                                            "or retired it just now. Everything else you typed " \
                                            "has been kept: pick another budget and submit again.")
      end

      def created_notice
        if @form.draft?
          "Draft saved. The finance team won't see it until you submit it.#{dropped_budget_note}"
        else
          "Expense submitted. You'll see status updates here."
        end
      end

      # A draft whose budget went saves without it, and the notice must say so.
      def dropped_budget_note
        return "" unless @form.dropped_stale_budget?

        " The budget you'd picked is no longer available, so it has been cleared. " \
          "Pick another one before you submit."
      end

      # The expense exists by now, so an attachment failure must not 500 (a
      # retry would duplicate the expense): point at edit to re-attach.
      def redirect_with_attachment_result(record_id, notice)
        attach_receipts(record_id)
        redirect_to admin_reimbursements_expenses_path, notice: notice
      rescue StandardError => e # any AR/ActiveStorage failure
        Honeybadger.notify(e, context: { expense_record_id: record_id })
        redirect_to edit_admin_reimbursements_expense_path(record_id),
                    alert: "The expense was saved, but uploading the receipt failed. " \
                           "Please attach it again here."
      end

      def expense_form_params
        params.require(:reimbursements_expense_form)
              .permit(:expense_type, :amount, :amount_excl_vat, :budget_record_id,
                      :description, :payment_reference, :payee_name_override,
                      :sort_code_override, :account_number_override,
                      :vat_acknowledged, :large_amount_acknowledged,
                      :payment_method, :foreign_amount, :foreign_currency,
                      :iban_override, :bic_override,
                      :save_as_draft, receipts: [])
      end

      def attach_receipts(record_id)
        @form.usable_receipts.each { |receipt| store.attach_receipt!(record_id, **receipt) }
      end
    end
  end
end
