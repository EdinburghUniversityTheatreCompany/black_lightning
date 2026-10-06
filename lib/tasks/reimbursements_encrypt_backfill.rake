namespace :reimbursements do
  # Re-saves every payee and expense record so existing plaintext bank details
  # become ciphertext. Run after deploying the keys and migrating, BEFORE turning
  # `support_unencrypted_data` off (docs/reimbursements/encryption-rollout.md):
  #
  #   RAILS_ENV=production bin/rails reimbursements:encrypt_backfill
  #
  # SAFE to re-run but NOT a no-op: `#encrypt` has no dirty check and picks a new
  # IV, so every row is rewritten and "processed N/N" counts rows touched, not
  # newly encrypted. `update_columns` bypasses validations, so the widen migration
  # must already have run or a long plaintext payee name is truncated.
  desc "Backfill: re-save reimbursements bank details so they encrypt at rest"
  task encrypt_backfill: :environment do
    # With the flag off Rails cannot READ a plaintext row, so every row would raise
    # and look like a data problem. Refuse up front: the rollout steps ran out of
    # order. Production sits with the flag off, so this is where an operator
    # encrypting a NEW column arrives.
    unless ActiveRecord::Encryption.config.support_unencrypted_data
      abort "Refusing to run: config.active_record.encryption.support_unencrypted_data is " \
            "false, so reading a plaintext row raises and every row would fail. Turn it on " \
            "and deploy first, then backfill, then turn it off again. " \
            "See docs/reimbursements/encryption-rollout.md."
    end

    failures = 0

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

      failures += failed
      puts "  #{model.name}: processed #{encrypted}/#{total}" \
           "#{failed.positive? ? " (#{failed} failed)" : ''}"
    end

    # Abort non-zero: the next step turns the flag off, after which a row that
    # failed to convert is unreadable and its details unrecoverable.
    abort "#{failures} record(s) failed to encrypt. Fix these before going further: " \
          "flipping support_unencrypted_data off now would make them unreadable." if failures.positive?

    puts "Done. Verify a sample row's raw column is ciphertext, then flip " \
         "config.active_record.encryption.support_unencrypted_data to false."
  end
end
