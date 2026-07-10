module Reimbursements
  ##
  # Producer notifications for a processed BACS batch — one email per payee,
  # listing the expenses of theirs that were just sent to EUSA for payment.
  # Ported from bedlam-bacs notifications.py / templates/producer_email.html.
  #
  # Unlike the EUSA email (a Graph draft the operator reviews and sends), these
  # go out through the app's normal ActionMailer delivery, +deliver_later+. All
  # arguments are primitives (strings, an array of hashes, a Date) so they
  # serialise cleanly for Solid Queue.
  class BatchMailer < ApplicationMailer
    def producer_notification(recipient_email:, recipient_name:, line_items:, bacs_date:, total:)
      @recipient_name = recipient_name
      @line_items = line_items
      @bacs_date = bacs_date
      @total = total

      mail(to: email_address_with_name(recipient_email, recipient_name),
           subject: "[Bedlam Fringe] #{line_items.size} #{'expense'.pluralize(line_items.size)} " \
                    "submitted for payment")
    end
  end
end
