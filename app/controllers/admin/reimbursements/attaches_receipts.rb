module Admin
  module Reimbursements
    ##
    # Attaching receipts posted to an expense, shared by every operator-facing
    # upload point (the producer's receipts gallery, the finance Review queue,
    # and the finance expense editor). Each caller words its own flash, but the
    # vetting — size, real content type, and the HEIC-to-JPEG conversion — is
    # done once, in ::Reimbursements::ReceiptIntake.
    module AttachesReceipts
      extend ActiveSupport::Concern

      # What to say when a post carried nothing we could attach and nothing to
      # complain about — a drop target that posted no files, or only things that
      # were never uploads. Here rather than in each controller, since both
      # upload points word the rest of their flashes differently but mean the
      # same thing by this.
      NOTHING_USABLE = "No usable receipt files (PDF or image, under the size limit)."

      private

      # Attaches every usable receipt in params[:receipts] and returns
      # [attached_count, error_messages] so the caller can report both what
      # landed and what didn't: a two-photo upload where one is unreadable
      # should still keep the good one.
      def attach_posted_receipts(expense)
        usable, rejected = ::Reimbursements::ReceiptIntake.from_params(params[:receipts]).partition(&:ok?)
        usable.each { |receipt| store.attach_receipt!(expense.record_id, **receipt.to_attachment) }
        [ usable.size, rejected.map(&:error) ]
      end

      # Answers a receipt add/remove the way the receipts-upload controller
      # expects: a turbo stream replacing #receipts-gallery (re-read, so the
      # gallery shows what is attached now), or a redirect for a plain form
      # post. `finance` points the gallery's remove buttons at the finance
      # routes instead of the producer's own.
      def respond_with_receipts_gallery(record_id, redirect_path:, upload_errors: [], notice: nil,
                                        finance: false, expense: nil)
        # Re-read only when the caller has no loaded expense: the gallery must
        # show what is attached NOW, and Expense#reload resets its receipts.
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
