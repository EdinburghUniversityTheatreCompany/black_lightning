module Reimbursements
  ##
  # Producer-facing emails about their expense claims. Ported from bedlam-bacs
  # `templates/rejection_email.html` — bedlam-bacs sent this through Microsoft
  # Graph; here it goes through ActionMailer (the operator app is multi-user and
  # can't use per-user Graph tokens for producer mail).
  #
  # Arguments are plain primitives, not the Expense PORO: the Review controller
  # delivers with +deliver_later+, and ActiveJob can only serialise primitives
  # (an Airtable-backed PORO has no GlobalID).
  class ExpenseMailer < ApplicationMailer
    def rejection_email(email:, payee_name:, auto_number:, amount:, budget_name:, description:, reason:)
      @payee_name = payee_name
      @auto_number = auto_number
      @amount = amount
      @budget_name = budget_name
      @description = description
      @reason = reason

      mail(to: email_address_with_name(email, payee_name),
           subject: "Your Bedlam expense ##{auto_number} was not approved")
    end
  end
end
