module Reimbursements
  # Daily nudge to budget owners about pending claims awaiting their sign-off, through the
  # website's own mailer (SMTP), not Graph. Only owners with a portal account can endorse, so
  # only they are emailed; the rest are covered by the finance override. Any one owner's
  # endorsement clears a claim, so every owner of a budget is nudged.
  class OwnerEndorsementDigestJob < ApplicationJob
    def perform
      pending = store.expenses.select(&:pending?)
      unmet_ids = OwnerReview.unmet_gate_expense_ids(pending)
      awaiting = pending.select { |expense| unmet_ids.include?(expense.record_id) }
      return if awaiting.empty?

      people_by_id = store.people.index_by(&:record_id)
      expenses_by_owner(awaiting).each do |owner_person_id, expenses|
        person = people_by_id[owner_person_id]
        next if person.nil?

        # Stored link first; email is the fallback only for an owner who never opened the portal,
        # because User emails are normalised on write and People emails aren't.
        user = person.user || (User.find_by(email: person.email) if person.email.present?)
        next if user.nil? # no portal account -> can't endorse; finance override covers them

        # deliver_now: the mail carries a whole expense collection, not worth serialising as job
        # args. Each send is isolated so one owner's failure doesn't abort the digest or retry the
        # whole job and re-mail everyone.
        begin
          OwnerEndorsementDigestMailer.digest(user, expenses).deliver_now
        rescue StandardError => e
          log_and_notify("Owner endorsement digest failed to send", e, context: { owner_person_id: owner_person_id })
        end
      end
    end

    private

    # Any one owner can endorse, so each claim goes to all of its budget's owners.
    def expenses_by_owner(awaiting)
      by_owner = Hash.new { |hash, key| hash[key] = [] }
      awaiting.each do |expense|
        expense.budget.owner_ids.each { |owner_id| by_owner[owner_id] << expense }
      end
      by_owner
    end
  end
end
