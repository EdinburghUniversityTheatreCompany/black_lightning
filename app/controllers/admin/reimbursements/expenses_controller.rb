module Admin
  module Reimbursements
    ##
    # A producer's own expenses: list with live status, receipt-first
    # submission (with save-as-draft), and editing while an expense is still a
    # draft or pending.
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
        # The budget went between the form-level check and the insert. Same
        # answer as the check itself: the form comes back with everything typed.
        budget_gone_error
        render_form(:new, "New Expense")
      end

      # Read-only view of the submitter's own claim at any status — so they can
      # check what they claimed and re-view their receipt while it's being paid.
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
        # Receipts are managed in the gallery on edit; the form only checks
        # the expense already carries one before a non-draft submit.
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

      # Discard an unsent draft entirely. Only a Draft can be deleted — a
      # Pending claim is with the finance team, so it's withdrawn (back to
      # Draft) via the edit form, not destroyed.
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

      # A producer followed a stale Edit link for a claim the finance team has
      # since picked up. Refuse the edit, but explain it rather than a bare 404.
      def expense_no_longer_editable
        # flash[:warning] (not alert/error) so this expected, not-broken state
        # renders as a neutral notice, not the alarming red "Oops…" error modal.
        redirect_to admin_reimbursements_expenses_path,
                    flash: { warning: "That claim is now with the finance team and can't be edited. " \
                                      "You can still view it from your expenses list." }
      end

      # The budgets the picker offers, memoized so the list the form is VALIDATED
      # against and the list a re-rendered form RENDERS are one read. Finance
      # deletes and deactivates budgets while these pages are open, so two reads
      # in one request could legitimately disagree — and a form validated
      # against a list it doesn't display can only produce an error the producer
      # cannot act on.
      def offerable_budgets
        @budgets ||= store.active_budgets
      end

      def offerable_budget_ids
        offerable_budgets.map(&:record_id)
      end

      # Re-render the submitter's own form with everything they entered. Losing
      # a filled-in claim is most of the harm in every failure here, so no path
      # out of create/update may do anything else.
      def render_form(template, title)
        @title = title
        @budgets = offerable_budgets
        render template, status: :unprocessable_entity
      end

      def budget_gone_error
        @form.errors.add(:budget_record_id, "is no longer available — the finance team removed " \
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

      # A draft whose budget went while the form was open saves WITHOUT it
      # rather than being refused (ExpenseForm#dropped_stale_budget?), so the
      # notice has to say the field was cleared: a budget they picked silently
      # coming back blank reads as the portal losing their choice.
      def dropped_budget_note
        return "" unless @form.dropped_stale_budget?

        " The budget you'd picked is no longer available, so it has been cleared — " \
          "pick another one before you submit."
      end

      # The expense exists by now, so an attachment failure must not 500
      # (retrying the form would duplicate the expense) — degrade to a flash
      # pointing at edit, where receipts can be re-attached.
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
