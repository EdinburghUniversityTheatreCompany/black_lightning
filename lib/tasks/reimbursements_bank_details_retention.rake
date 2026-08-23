namespace :reimbursements do
  # Dry run of the nightly retention sweep: names the payees whose bank details
  # would be cleared, and clears nothing.
  #
  # Worth running before the sweep is first let loose on real data, and any time
  # its rules change. Clearing is IRREVERSIBLE — the columns are encrypted with
  # no plaintext behind them and no backup of the values — so the one cheap
  # protection against a rule that reads more claims as finished than it should
  # is a human looking at the list first.
  #
  #   RAILS_ENV=production bin/rails reimbursements:bank_details_retention_preview
  #
  # The sweep itself runs nightly as Reimbursements::BankDetailsRetentionJob
  # (config/recurring.yml); there is no rake entry point for it on purpose.
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
      # Last four only: a preview meant to be pasted into a chat with the
      # committee must not be the one place the full number turns up.
      puts format("  %-30s %-30s last activity %s",
                  person&.name.to_s.truncate(30),
                  person&.email.to_s.truncate(30),
                  [ details.updated_at, *person&.expenses&.map(&:updated_at) ].compact.max&.to_date)
    end
    puts "\nNothing has been changed. The nightly job (Reimbursements::BankDetailsRetentionJob) " \
         "is what actually clears them."
  end
end
