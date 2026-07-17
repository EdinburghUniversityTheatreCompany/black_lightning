module Reimbursements
  ##
  # Daily nudge to budget owners about pending claims charged to their budgets
  # that still await their sign-off (the E3 gate). Sent through the website's
  # own mailer (SMTP), not the Graph shared mailbox. Only owners with a portal
  # account can endorse, so only they are emailed — owners without an account
  # are covered by the finance override path instead. Any one owner's
  # endorsement clears a claim, so every owner of a budget is nudged about it.
  class OwnerEndorsementDigestJob < ApplicationJob
    def perform
      pending = store.expenses.select(&:pending?)
      unmet_ids = OwnerReview.unmet_gate_expense_ids(pending)
      awaiting = pending.select { |expense| unmet_ids.include?(expense.record_id) }
      return if awaiting.empty?

      people_by_id = store.people.index_by(&:record_id)
      expenses_by_owner(awaiting).each do |owner_person_id, expenses|
        person = people_by_id[owner_person_id]
        next if person.nil? || person.email.blank?

        user = User.find_by(email: person.email)
        next if user.nil? # no portal account -> can't endorse; finance override covers them

        # deliver_now (not _later): the mail carries Airtable POROs ActiveJob
        # can't serialize as job args, and we're already inside a background job.
        # Isolate each send so one owner's failure doesn't abort the digest (or
        # trigger a whole-job retry that re-mails everyone).
        begin
          OwnerEndorsementDigestMailer.digest(user, expenses).deliver_now
        rescue StandardError => e
          log_and_notify("Owner endorsement digest failed to send", e, context: { owner_person_id: owner_person_id })
        end
      end
    end

    private

    # Fan each awaiting claim out to every owner of its budget — any one of them
    # can endorse it, so all of them should hear about it.
    def expenses_by_owner(awaiting)
      by_owner = Hash.new { |hash, key| hash[key] = [] }
      awaiting.each do |expense|
        expense.budget.owner_ids.each { |owner_id| by_owner[owner_id] << expense }
      end
      by_owner
    end
  end
end
