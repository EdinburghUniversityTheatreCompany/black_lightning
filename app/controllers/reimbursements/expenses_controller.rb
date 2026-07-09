module Reimbursements
  ##
  # A producer's own expenses: list with live status, receipt-first
  # AI-prefilled submission, and editing while still Pending.
  class ExpensesController < BaseController
    def index
      if params[:refresh].present?
        store.refresh_expenses!
        redirect_to reimbursements_expenses_path and return
      end

      @title = "My Reimbursements"
      @expenses = current_person ? store.expenses_for(current_person.record_id) : []
    end

    def new
      @title = "New Expense"
      @form = ExpenseForm.new
      @budgets = store.active_budgets
    end

    def create
      @form = ExpenseForm.new(expense_form_params)
      unless @form.valid?
        @title = "New Expense"
        @budgets = store.active_budgets
        render :new, status: :unprocessable_entity
        return
      end

      person = person_link.ensure_person!(current_user)
      expense = store.create_expense!(@form.create_attrs(person.record_id))
      attach_receipts(expense.record_id)
      redirect_to reimbursements_expenses_path,
                  notice: "Expense submitted — you'll see status updates here."
    end

    def edit
      @expense = find_own_editable_expense!(params[:id])
      @title = "Edit Expense"
      @form = ExpenseForm.from_expense(@expense)
      @budgets = store.active_budgets
    end

    def update
      @expense = find_own_editable_expense!(params[:id])
      @form = ExpenseForm.new(expense_form_params.merge(require_receipts: false))
      unless @form.valid?
        @title = "Edit Expense"
        @budgets = store.active_budgets
        render :edit, status: :unprocessable_entity
        return
      end

      store.update_expense!(@expense.record_id, @form.update_attrs)
      attach_receipts(@expense.record_id)
      redirect_to reimbursements_expenses_path, notice: "Expense updated."
    end

    # Receipt-first prefill: the form posts the receipt(s) here before
    # submission; extraction failures return ok: false and the form stays
    # manual (never a blocker).
    def extract
      files = Array(params[:receipts]).compact_blank
      extraction = extractor.extract(receipts: files.map { |f| receipt_payload(f) },
                                     budgets: store.active_budgets)
      render json: extraction_json(extraction)
    end

    private

    # Submitters may only touch their own expenses, and only while Pending
    # (once review picks an expense up it's the finance team's).
    def find_own_editable_expense!(record_id)
      expense = store.find_expense(record_id)
      unless expense && current_person && expense.person&.record_id == current_person.record_id &&
             expense.editable?
        raise ActiveRecord::RecordNotFound
      end
      expense
    end

    def expense_form_params
      params.require(:reimbursements_expense_form)
            .permit(:expense_type, :amount, :amount_excl_vat, :budget_record_id,
                    :description, :payment_reference, :payee_name_override,
                    :sort_code_override, :account_number_override,
                    :vat_itemised, :vat_acknowledged, receipts: [])
    end

    def attach_receipts(record_id)
      @form.receipts.each do |file|
        store.attach_receipt!(record_id, filename: file.original_filename,
                                         content_type: file.content_type, bytes: file.read)
      end
    end

    def receipt_payload(file)
      { filename: file.original_filename, content_type: file.content_type, bytes: file.read }
    end

    def extraction_json(extraction)
      return { ok: false, error: extraction.error } unless extraction.ok?

      excl_vat = if extraction.total_amount && extraction.vat_itemised && extraction.vat_amount
        extraction.total_amount - extraction.vat_amount
      else
        extraction.total_amount
      end
      {
        ok: true,
        merchant: extraction.merchant,
        total_amount: extraction.total_amount&.to_s("F"),
        amount_excl_vat: excl_vat&.to_s("F"),
        vat_itemised: extraction.vat_itemised,
        suggested_description: extraction.suggested_description,
        suggested_budget_record_id: extraction.suggested_budget_record_id,
        suggested_payment_reference: extraction.suggested_payment_reference
      }
    end
  end
end
