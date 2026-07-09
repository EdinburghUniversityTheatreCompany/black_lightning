module Admin
  module Reimbursements
    ##
    # Removing a receipt from an own, still-Pending expense. Airtable removes
    # attachments by rewriting the field with the survivors, so an expense
    # must always keep at least one receipt: add the replacement first.
    class ReceiptsController < BaseController
      def destroy
        expense = find_own_editable_expense!(params[:expense_id])

        if expense.receipts.size <= 1
          redirect_to edit_admin_reimbursements_expense_path(expense.record_id),
                      alert: "You can't remove the last receipt. Add the replacement first, then remove this one."
          return
        end

        store.remove_receipt!(expense.record_id, params[:id])
        redirect_to edit_admin_reimbursements_expense_path(expense.record_id),
                    notice: "Receipt removed."
      end
    end
  end
end
