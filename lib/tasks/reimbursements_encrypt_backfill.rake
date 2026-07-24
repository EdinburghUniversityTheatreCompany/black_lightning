namespace :reimbursements do
  # One-off backfill for the bank-details-at-rest rollout (Track F). After the
  # `encrypts` declarations ship with `support_unencrypted_data = true`, existing
  # rows are still plaintext and are only re-encrypted when next saved. This task
  # rewrites every payee record so its bank details land as ciphertext.
  #
  # `#encrypt` re-encrypts the record's encrypted attributes in place and saves
  # only if something changed, so the task is idempotent — re-running it after a
  # partial run (or on an already-encrypted row) is a no-op for that row.
  #
  # Run in production AFTER deploying the encryption keys, and BEFORE flipping
  # `support_unencrypted_data` off:
  #
  #   RAILS_ENV=production bin/rails reimbursements:encrypt_backfill
  #
  # See docs/reimbursements/encryption-rollout.md for the full sequence.
  desc "Backfill: re-save reimbursements bank details so they encrypt at rest"
  task encrypt_backfill: :environment do
    [ Reimbursements::PaymentDetails, Reimbursements::Expense ].each do |model|
      total = model.count
      encrypted = 0
      failed = 0

      puts "Encrypting #{total} #{model.name} record(s)..."
      model.find_each do |record|
        record.encrypt
        encrypted += 1
      rescue => e
        failed += 1
        warn "  ! #{model.name}##{record.id} failed: #{e.class}: #{e.message}"
      end

      puts "  #{model.name}: processed #{encrypted}/#{total}" \
           "#{failed.positive? ? " (#{failed} failed)" : ''}"
    end

    puts "Done. Verify a sample row's raw column is ciphertext, then flip " \
         "config.active_record.encryption.support_unencrypted_data to false."
  end
end
