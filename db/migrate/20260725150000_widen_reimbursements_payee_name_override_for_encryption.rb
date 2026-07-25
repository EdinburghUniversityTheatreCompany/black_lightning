##
# Track F encrypts reimbursements_expenses.payee_name_override, and AR
# Encryption stores a JSON envelope (base64 IV + ciphertext + auth tag) rather
# than the bare value: measured against the real encryptor, a low-redundancy
# plaintext of ~124 characters already exceeds 255 bytes once encrypted, and 255
# characters lands at ~394. varchar(255) therefore no longer holds every value
# the pre-encryption column held.
#
# Rails' auto-injected validate_column_size guard does not catch this — it
# validates the DECRYPTED value's length against the column limit — so the
# failure mode was ActiveRecord::ValueTooLong (a 500 on the invoice-mode prefill
# path) under strict MySQL, or a silently truncated ciphertext whose unparseable
# JSON support_unencrypted_data then hands back as "plaintext" straight onto the
# BACS spreadsheet.
#
# payee_name_override is the only member of the third-party override trio that
# carries free text; sort_code_override / account_number_override are format-
# validated to 6 and 8 digits on every write path (~82 bytes encrypted), as are
# reimbursements_payment_details.sort_code / .account_number, so those stay
# string(255) — see test/models/reimbursements/encryption_test.rb, which pins
# both measurements.
class WidenReimbursementsPayeeNameOverrideForEncryption < ActiveRecord::Migration[8.1]
  def up
    # safety_assured: strong_migrations blocks change_column outright. This is a
    # widening varchar(255) -> TEXT on a table with a few hundred rows, migrated
    # from Airtable weeks ago, so the copy-table ALTER is sub-second; and the
    # alternative (add / dual-write / backfill / swap) would move ciphertext
    # between columns for no benefit at this size.
    safety_assured { change_column :reimbursements_expenses, :payee_name_override, :text }
  end

  # Reversible so a dev rollback works, but narrowing back to varchar(255) will
  # truncate (strict MySQL: refuse) any ciphertext over 255 bytes — i.e. exactly
  # the values this migration exists to allow.
  def down
    safety_assured { change_column :reimbursements_expenses, :payee_name_override, :string }
  end
end
