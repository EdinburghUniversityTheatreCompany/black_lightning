module Reimbursements
  ##
  # The "you've been paid" note to a producer once EUSA's actuals confirm their
  # expense was paid (sent from Reconcile → Apply). Deferred in bedlam-bacs;
  # added here. A plain ActionMailer message (not Microsoft Graph) — it goes to
  # the payee's own email, so it needs no shared-mailbox identity.
  class PaymentMailer < ApplicationMailer
    def payment_confirmation(person, expenses)
      return if person.nil? || person.email.blank?

      @person = person
      @expenses = Array(expenses)
      subject = "EUSA has paid your expense#{'s' if @expenses.size > 1}"
      mail(to: email_address_with_name(person.email, person.name), subject: subject)
    end
  end
end
