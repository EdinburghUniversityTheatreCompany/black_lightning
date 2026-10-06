module Admin
  module Reimbursements
    ##
    # Attaching receipts posted to an expense, shared by every upload point.
    # Vetting is done once, in ::Reimbursements::ReceiptIntake.
    module AttachesReceipts
      extend ActiveSupport::Concern

      NOTHING_USABLE = "No usable receipt files (PDF or image, under the size limit)."

      private

      # Returns [attached_count, error_messages]: a two-photo upload with one
      # unreadable keeps the good one.
      def attach_posted_receipts(expense)
        usable, rejected = ::Reimbursements::ReceiptIntake.from_params(params[:receipts]).partition(&:ok?)
        usable.each { |receipt| store.attach_receipt!(expense.record_id, **receipt.to_attachment) }
        [ usable.size, rejected.map(&:error) ]
      end

      # Answers with a turbo stream replacing #receipts-gallery, or a redirect for
      # a plain post. `finance` points the remove buttons at the finance routes.
      def respond_with_receipts_gallery(record_id, redirect_path:, upload_errors: [], notice: nil,
                                        finance: false, expense: nil)
        # Expense#reload resets its receipts, so the gallery shows what is attached now.
        expense = expense&.reload || store.find_expense!(record_id)
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              "receipts-gallery",
              partial: "admin/reimbursements/expenses/receipts_gallery",
              locals: { expense: expense, upload_errors: upload_errors, finance: finance }
            )
          end
          format.html do
            redirect_to redirect_path, notice: notice, alert: upload_errors.presence&.to_sentence
          end
        end
      end
    end
  end
end
