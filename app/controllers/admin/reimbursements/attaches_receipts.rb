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
      # unreadable keeps the good one, and a post with no file at all reads NOTHING_USABLE.
      def attach_posted_receipts(expense)
        intakes = ::Reimbursements::ReceiptIntake.from_params(params[:receipts])
        return [ 0, [ NOTHING_USABLE ] ] if intakes.empty?

        usable, rejected = intakes.partition(&:ok?)
        usable.each { |receipt| store.attach_receipt!(expense.record_id, **receipt.to_attachment) }
        [ usable.size, rejected.map(&:error) ]
      end

      # Answers with a turbo stream replacing #receipts-gallery: receipts_upload_controller
      # is the only client. `finance` points the remove buttons at the finance routes.
      def respond_with_receipts_gallery(expense, upload_errors: [], finance: false)
        # Expense#reload resets its receipts, so the gallery shows what is attached now.
        expense = expense.reload
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              "receipts-gallery",
              partial: "admin/reimbursements/expenses/receipts_gallery",
              locals: { expense: expense, upload_errors: upload_errors, finance: finance }
            )
          end
        end
      end
    end
  end
end
