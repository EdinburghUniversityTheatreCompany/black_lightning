module Admin
  module Reimbursements
    ##
    # Immediate uploads and per-receipt removal on an editable expense. Both answer
    # a turbo stream replacing #receipts-gallery (HTML: redirect to edit).
    class ReceiptsController < BaseController
      include AttachesReceipts

      def create
        expense = find_own_editable_expense!(params[:expense_id])
        _, upload_errors = attach_posted_receipts(expense)

        respond_with_gallery(expense, upload_errors: upload_errors,
                                      notice: upload_errors.empty? ? "Receipt added." : nil)
      end

      def destroy
        expense = find_own_editable_expense!(params[:expense_id])

        store.remove_receipt!(expense.record_id, params[:id])
        respond_with_gallery(expense, notice: "Receipt removed.")
      rescue ::Reimbursements::DatabaseStore::LastReceiptError
        respond_with_gallery(expense,
                             upload_errors: [ "You can't remove the last receipt. Add the replacement first, then remove this one." ])
      end

      private

      def respond_with_gallery(expense, upload_errors: [], notice: nil)
        respond_with_receipts_gallery(expense, upload_errors: upload_errors, notice: notice,
                                      redirect_path: edit_admin_reimbursements_expense_path(expense.record_id))
      end
    end
  end
end
