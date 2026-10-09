module Admin
  module Reimbursements
    ##
    # Immediate uploads and per-receipt removal on an editable expense. Both answer
    # a turbo stream replacing #receipts-gallery.
    class ReceiptsController < BaseController
      include AttachesReceipts

      def create
        expense = find_own_editable_expense!(params[:expense_id])
        _, upload_errors = attach_posted_receipts(expense)

        respond_with_receipts_gallery(expense, upload_errors: upload_errors)
      end

      def destroy
        expense = find_own_editable_expense!(params[:expense_id])

        store.remove_receipt!(expense.record_id, params[:id])
        respond_with_receipts_gallery(expense)
      rescue ::Reimbursements::DatabaseStore::LastReceiptError
        respond_with_receipts_gallery(expense,
                                      upload_errors: [ "You can't remove the last receipt. Add the replacement first, then remove this one." ])
      end
    end
  end
end
