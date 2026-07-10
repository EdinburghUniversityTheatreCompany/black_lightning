module Admin
  module Reimbursements
    ##
    # Receipts on an editable expense: immediate uploads from the gallery's
    # drop target and per-receipt removal. Both respond with a turbo stream
    # replacing #receipts-gallery (HTML fallback: redirect to edit).
    class ReceiptsController < BaseController
      def create
        expense = find_own_editable_expense!(params[:expense_id])
        upload_errors = attach_uploads(expense)

        respond_with_gallery(expense.record_id, upload_errors: upload_errors,
                                                notice: upload_errors.empty? ? "Receipt added." : nil)
      end

      def destroy
        expense = find_own_editable_expense!(params[:expense_id])

        store.remove_receipt!(expense.record_id, params[:id])
        respond_with_gallery(expense.record_id, notice: "Receipt removed.")
      rescue ::Reimbursements::Store::LastReceiptError
        respond_with_gallery(params[:expense_id],
                             upload_errors: [ "You can't remove the last receipt. Add the replacement first, then remove this one." ])
      end

      private

      def attach_uploads(expense)
        files = Array(params[:receipts]).compact_blank
        return [ "No files received." ] if files.empty?

        files.filter_map do |file|
          if !::Reimbursements::ExpenseForm::ALLOWED_RECEIPT_TYPES.include?(file.content_type)
            "#{file.original_filename} must be a PDF or a photo (JPEG/PNG/WEBP)."
          elsif file.size > ::Reimbursements::ExpenseForm::MAX_RECEIPT_BYTES
            "#{file.original_filename} must be 5 MB or smaller."
          else
            store.attach_receipt!(expense.record_id, filename: file.original_filename,
                                                     content_type: file.content_type, bytes: file.read)
            nil
          end
        end
      end

      def respond_with_gallery(record_id, upload_errors: [], notice: nil)
        expense = store.find_expense!(record_id)
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              "receipts-gallery",
              partial: "admin/reimbursements/expenses/receipts_gallery",
              locals: { expense: expense, upload_errors: upload_errors }
            )
          end
          format.html do
            redirect_to edit_admin_reimbursements_expense_path(record_id),
                        notice: notice, alert: upload_errors.presence&.to_sentence
          end
        end
      end
    end
  end
end
