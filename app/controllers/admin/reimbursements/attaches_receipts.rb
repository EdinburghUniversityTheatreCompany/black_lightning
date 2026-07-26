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
    end
  end
end
