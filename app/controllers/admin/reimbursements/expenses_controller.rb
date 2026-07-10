module Admin
  module Reimbursements
    ##
    # A producer's own expenses: list with live status, receipt-first
    # AI-prefilled submission (with save-as-draft), and editing while an
    # expense is still a draft or pending.
    class ExpensesController < BaseController
      def index
        if params[:refresh].present?
          store.refresh_expenses!
          redirect_to admin_reimbursements_expenses_path and return
        end

        @title = "My Reimbursements"
        @expenses = current_person ? store.expenses_for(current_person.record_id) : []
      end

      def new
        @title = "New Expense"
        @form = ::Reimbursements::ExpenseForm.new
        @budgets = store.active_budgets
      end

      def create
        @form = ::Reimbursements::ExpenseForm.new(expense_form_params)
        unless @form.valid?
          @title = "New Expense"
          @budgets = store.active_budgets
          render :new, status: :unprocessable_entity
          return
        end

        person = person_link.ensure_person!(current_user)
        expense = store.create_expense!(@form.create_attrs(person.record_id))
        redirect_with_attachment_result(expense.record_id, created_notice)
      end

      def edit
        @expense = find_own_editable_expense!(params[:id])
        @title = "Edit Expense"
        @form = ::Reimbursements::ExpenseForm.from_expense(@expense)
        @budgets = store.active_budgets
      end

      def update
        @expense = find_own_editable_expense!(params[:id])
        # Editing doesn't force a re-upload, EXCEPT when the expense has no
        # receipts yet (e.g. a bare draft) — submitting must not produce a
        # receipt-less Pending expense.
        @form = ::Reimbursements::ExpenseForm.new(
          expense_form_params.merge(require_receipts: @expense.receipts.empty?)
        )
        unless @form.valid?
          @title = "Edit Expense"
          @budgets = store.active_budgets
          render :edit, status: :unprocessable_entity
          return
        end

        store.update_expense!(@expense.record_id, @form.update_attrs)
        notice = @form.draft? ? "Draft saved." : "Expense updated."
        redirect_with_attachment_result(@expense.record_id, notice)
      end

      # Receipt-first prefill: the form posts the receipt(s) here before
      # submission; extraction failures return ok: false and the form stays
      # manual (never a blocker). Files are gated here like on submit — this
      # endpoint base64s them into RAM for Gemini.
      def extract
        files = Array(params[:receipts]).compact_blank.select do |file|
          ::Reimbursements::ExpenseForm::ALLOWED_RECEIPT_TYPES.include?(file.content_type) &&
            file.size <= ::Reimbursements::ExpenseForm::MAX_RECEIPT_BYTES
        end
        if files.empty?
          render json: { ok: false, error: "no usable receipt files" }
          return
        end

        extraction = extractor.extract(receipts: files.map { |f| receipt_payload(f) },
                                       budgets: store.active_budgets)
        render json: extraction_json(extraction)
      end

      private

      def created_notice
        if @form.draft?
          "Draft saved. The finance team won't see it until you submit it."
        else
          "Expense submitted. You'll see status updates here."
        end
      end

      # The expense exists by now, so an attachment failure must not 500
      # (retrying the form would duplicate the expense) — degrade to a flash
      # pointing at edit, where receipts can be re-attached.
      def redirect_with_attachment_result(record_id, notice)
        attach_receipts(record_id)
        redirect_to admin_reimbursements_expenses_path, notice: notice
      rescue ::Reimbursements::Airtable::Error => e
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
                      :vat_itemised, :vat_acknowledged, :save_as_draft, receipts: [])
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

        excl_vat = extraction.amount_excl_vat || extraction.total_amount
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
end
