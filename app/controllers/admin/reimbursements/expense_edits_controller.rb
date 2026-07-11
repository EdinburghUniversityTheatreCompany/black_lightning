module Admin
  module Reimbursements
    ##
    # Finance-only editing of a single expense at ANY status — Pending,
    # Approved, Submitted AND Paid. The Business Manager wants full
    # flexibility, so there is deliberately NO +editable?+/status guard here
    # (that guard belongs to the producer portal path, where a submitter may
    # only touch their own Draft/Pending expense).
    #
    # Reachable from the Review cards' "Edit (any status)" link and from a
    # lookup by auto-number or Airtable record id (so a Submitted/Paid expense
    # that never appears on the Review tabs can still be found). Edits persist
    # through +store.update_expense!+, which is status-agnostic; a Submitted or
    # Paid expense shows a clear note that the edit won't change what EUSA has
    # already processed.
    #
    # Gated by the finance grid permission (`:manage, :reimbursements_finance`)
    # via FinanceController.
    class ExpenseEditsController < FinanceController
      # Injection seam for tests: the modulus checker (from the vendored Pay.UK
      # rule files in production; a fake in functional tests).
      class_attribute :checker_builder, default: -> { ::Reimbursements::ModulusCheck.default_checker }

      helper_method :modulus_checker

      # Lookup: resolve a typed auto-number or record id to its edit page.
      def find
        @title = "Find an Expense"
        query = params[:q].to_s.strip
        return if query.blank?

        expense = lookup_expense(query)
        if expense
          redirect_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
        else
          flash.now[:alert] = "No expense matches \"#{query}\". Try its number (e.g. 42) or record id."
        end
      end

      def edit
        @expense = find_expense!
        @title = "Edit ##{@expense.auto_number}"
        @budgets = store.active_budgets
      end

      def update
        expense = find_expense!
        store.update_expense!(expense.record_id, update_attrs)
        redirect_to_edit(expense, notice: "Saved changes to ##{expense.auto_number}.")
      end

      def add_receipts
        expense = find_expense!
        files = Array(params[:receipts]).compact_blank.select do |file|
          ::Reimbursements::ExpenseForm::ALLOWED_RECEIPT_TYPES.include?(file.content_type) &&
            file.size <= ::Reimbursements::ExpenseForm::MAX_RECEIPT_BYTES
        end
        if files.empty?
          redirect_to_edit(expense, alert: "No usable receipt files (PDF or image, under the size limit).")
          return
        end

        files.each do |file|
          store.attach_receipt!(expense.record_id, filename: file.original_filename,
                                                   content_type: file.content_type, bytes: file.read)
        end
        redirect_to_edit(expense, notice: "Attached #{files.size} receipt(s) to ##{expense.auto_number}.")
      rescue ::Reimbursements::Airtable::Error => e
        redirect_to_edit(expense, alert: "Couldn't attach the receipt: #{e.message}")
      end

      def remove_receipt
        expense = find_expense!
        store.remove_receipt!(expense.record_id, params[:attachment_id])
        redirect_to_edit(expense, notice: "Removed a receipt from ##{expense.auto_number}.")
      rescue ::Reimbursements::Store::LastReceiptError
        redirect_to_edit(expense, alert: "Can't remove the last receipt from a submitted expense.")
      rescue ::Reimbursements::Airtable::Error => e
        redirect_to_edit(expense, alert: "Couldn't remove the receipt: #{e.message}")
      end

      private

      def modulus_checker
        @modulus_checker ||= checker_builder.call
      end

      def find_expense!
        expense = store.find_expense!(params[:id])
        raise ActiveRecord::RecordNotFound if expense.nil?

        expense
      end

      # Match on Airtable record id first, then on the visible auto-number.
      def lookup_expense(query)
        by_id = store.find_expense(query)
        return by_id if by_id

        store.expenses.find { |e| e.auto_number.to_s == query.sub(/\A#/, "") }
      end

      def update_attrs
        attrs = {
          amount: params[:amount].presence,
          description: params[:description],
          payment_reference: params[:payment_reference],
          nominal_code_override: params[:nominal_code_override].to_s,
          budget_record_id: params[:budget_record_id].presence,
          payee_name_override: params[:payee_name_override].to_s,
          sort_code_override: params[:sort_code_override].to_s,
          account_number_override: params[:account_number_override].to_s
        }
        # Only write excl-VAT when a positive value is given (0 means "not yet
        # known", leave the field alone), mirroring the Review save.
        excl_vat = params[:amount_excl_vat].to_f
        attrs[:amount_excl_vat] = excl_vat if excl_vat.positive?
        attrs
      end

      def redirect_to_edit(expense, flash)
        redirect_to edit_admin_reimbursements_expense_edit_path(expense.record_id), **flash
      end
    end
  end
end
