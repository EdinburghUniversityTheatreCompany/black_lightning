namespace :reimbursements do
  # Dry run of the nightly retention sweep: names the payees whose bank details
  # would be cleared, and clears nothing. Run it whenever the rules change:
  # clearing is IRREVERSIBLE (no plaintext, no backup), so a human reading the
  # list first is the only protection against a rule that reads too many claims
  # as finished. The sweep itself is BankDetailsRetentionJob; there is no rake
  # entry point for it on purpose.
  #
  #   RAILS_ENV=production bin/rails reimbursements:bank_details_retention_preview
  desc "Preview: which payees' bank details the retention sweep would clear"
  task bank_details_retention_preview: :environment do
    stale = Reimbursements::BankDetailsRetention.stale
    period = Reimbursements::BankDetailsRetention::RETENTION_PERIOD.inspect

    if stale.empty?
      puts "No payee has bank details older than #{period} of inactivity. Nothing would be cleared."
      next
    end

    puts "#{stale.size} payee(s) would have their bank details cleared (no claim activity " \
         "in #{period}):"
    stale.each do |details|
      person = details.person
      # No bank digits at all: this is pasted into a chat with the committee.
      puts format("  %-30s %-30s last activity %s",
                  person.name.to_s.truncate(30),
                  person.email.to_s.truncate(30),
                  Reimbursements::BankDetailsRetention.last_activity(details).to_date)
    end
    puts "\nNothing has been changed. The nightly job (Reimbursements::BankDetailsRetentionJob) " \
         "is what actually clears them."
  end
end
