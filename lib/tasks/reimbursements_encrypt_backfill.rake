namespace :reimbursements do
  # One-off backfill for the bank-details-at-rest rollout. After the
  # `encrypts` declarations ship with `support_unencrypted_data = true`, existing
  # rows are still plaintext and are only re-encrypted when next saved. This task
  # rewrites every payee record so its bank details land as ciphertext.
  #
  # SAFE to re-run, but NOT a no-op. `#encrypt` calls `update_columns` with
  # freshly built assignments unconditionally — there is no dirty check — and the
  # encryption is non-deterministic, so every run picks a new IV and rewrites new
  # ciphertext for EVERY row, already-encrypted rows included. The end state is
  # correct either way, but the printed "processed N/N" is a count of rows
  # touched, not of rows newly encrypted: it says nothing about how much was left
  # to do, so don't read it as progress across a resumed partial run.
  #
  # `update_columns` also bypasses validations, so the columns must already be
  # wide enough to hold the ciphertext BEFORE this runs — see
  # 20260725150000_widen_reimbursements_payee_name_override_for_encryption, which
  # must be migrated first or a long plaintext payee name is truncated here.
  #
  # Run in production AFTER deploying the encryption keys and migrating, and
  # BEFORE flipping `support_unencrypted_data` off:
  #
  #   RAILS_ENV=production bin/rails reimbursements:encrypt_backfill
  #
  # See docs/reimbursements/encryption-rollout.md for the full sequence.
  desc "Backfill: re-save reimbursements bank details so they encrypt at rest"
  task encrypt_backfill: :environment do
    # With support_unencrypted_data off, Rails cannot READ a plaintext row at all, so
    # every row this task touches raises and nothing gets encrypted. Refuse up front and
    # name the flag: reported one row at a time it looks like a data problem, when in fact
    # the rollout steps have been run out of order (the flag must go back on, and deploy,
    # before backfilling). Production sits with the flag off, so this is the state an
    # operator encrypting a NEW column arrives in.
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

    # Abort loudly rather than printing the flip-the-flag advice: the next step
    # turns support_unencrypted_data off, after which any row this task failed
    # to convert raises on read and its bank details are unrecoverable. Exiting
    # 0 here would let a scripted rollout march straight past that.
    abort "#{failures} record(s) failed to encrypt. Fix these before going further: " \
          "flipping support_unencrypted_data off now would make them unreadable." if failures.positive?

    puts "Done. Verify a sample row's raw column is ciphertext, then flip " \
         "config.active_record.encryption.support_unencrypted_data to false."
  end
end
