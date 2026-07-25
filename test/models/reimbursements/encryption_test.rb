require "test_helper"

module Reimbursements
  # Track F: bank details are encrypted at rest. These tests prove the model
  # reads/writes plaintext transparently while the underlying DB column holds
  # ciphertext, so a DB/backup/replica dump never exposes UK bank details.
  class EncryptionTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    # Read the actual bytes stored in the column, bypassing AR's decryption, so
    # we assert on what a `mysqldump` / replica would actually reveal.
    def raw_column(model, id, column)
      # column/table are trusted literals from the test; only id is data, bound
      # via sanitize_sql_array so this stays a parameterised query.
      quoted_column = model.connection.quote_column_name(column)
      sql = model.sanitize_sql_array(
        [ "SELECT #{quoted_column} FROM #{model.table_name} WHERE id = ?", id ]
      )
      model.connection.select_value(sql)
    end

    test "PaymentDetails encrypts sort_code, account_number and notes at rest" do
      person = create_reimbursements_person(
        name: "Cipher Cassie", email: "cassie@example.com",
        sort_code: "08-99-99", account_number: "66374958",
        notes: "Bank details updated: account ****4958"
      )
      details = person.payment_details

      # The model reads plaintext transparently (BACS builder + modulus check
      # rely on this — see #effective_* / ModulusCheck).
      assert_equal "08-99-99", details.sort_code
      assert_equal "66374958", details.account_number

      # But the raw column no longer contains the plaintext digits.
      raw_account = raw_column(PaymentDetails, details.id, "account_number")
      raw_sort = raw_column(PaymentDetails, details.id, "sort_code")
      raw_notes = raw_column(PaymentDetails, details.id, "notes")
      assert_not_includes raw_account.to_s, "66374958", "account number must not be stored in plaintext"
      assert_not_includes raw_sort.to_s, "08-99-99", "sort code must not be stored in plaintext"
      assert_not_includes raw_notes.to_s, "****4958", "notes must not be stored in plaintext"

      # ciphertext_for confirms the stored value differs from the plaintext.
      assert_not_equal "66374958", details.ciphertext_for(:account_number)
      assert_not_equal "08-99-99", details.ciphertext_for(:sort_code)
    end

    test "Expense encrypts the third-party override trio at rest" do
      expense = create_reimbursements_expense(
        receipt: false,
        payee_name_override: "Third Party Ltd",
        sort_code_override: "20-20-20",
        account_number_override: "50502366"
      )

      assert_equal "Third Party Ltd", expense.payee_name_override
      assert_equal "20-20-20", expense.sort_code_override
      assert_equal "50502366", expense.account_number_override

      raw_account = raw_column(Expense, expense.id, "account_number_override")
      raw_sort = raw_column(Expense, expense.id, "sort_code_override")
      raw_payee = raw_column(Expense, expense.id, "payee_name_override")
      assert_not_includes raw_account.to_s, "50502366", "override account number must not be stored in plaintext"
      assert_not_includes raw_sort.to_s, "20-20-20", "override sort code must not be stored in plaintext"
      assert_not_includes raw_payee.to_s, "Third Party Ltd", "override payee name must not be stored in plaintext"

      assert_not_equal "50502366", expense.ciphertext_for(:account_number_override)
    end

    # S1: encryption inflates the stored value (a JSON envelope of base64 IV +
    # ciphertext + auth tag), so a plaintext that fit varchar(255) before Track F
    # may not fit afterwards. Measured against the real encryptor: any
    # low-redundancy plaintext of ~124 characters or more already exceeds 255
    # bytes once encrypted, and 255 characters lands at ~394. Rails' own
    # validate_column_size guard checks the DECRYPTED value's length, so it never
    # caught this; under strict MySQL the save raised ValueTooLong (a 500 on a
    # path that worked pre-encryption), and under a non-strict server the
    # ciphertext would be silently truncated into unparseable JSON that
    # support_unencrypted_data then hands back as "plaintext" — straight onto the
    # BACS spreadsheet as a payee name.
    #
    # payee_name_override is the one member of the third-party override trio that
    # carries free text (sort_code_override / account_number_override are format-
    # validated to 6 and 8 digits on every write path), and invoice-mode AI prefill
    # reads the payee line straight off an invoice, so a long value is reachable.
    test "Expense round-trips a payee name override whose ciphertext exceeds 255 bytes" do
      # Low-redundancy so AR's built-in compression can't shrink it back under
      # the old limit: a repetitive 255-character string compresses to ~95 bytes.
      long_payee = SecureRandom.alphanumeric(200)
      assert_operator ciphertext_bytesize(long_payee), :>, 255,
                      "test premise: this plaintext must encrypt past varchar(255)"

      expense = create_reimbursements_expense(
        receipt: false,
        payee_name_override: long_payee,
        sort_code_override: "20-20-20",
        account_number_override: "50502366"
      )

      assert_equal long_payee, expense.reload.payee_name_override,
                   "a long payee name override must survive the DB round trip intact"
    end

    # Rails' auto-injected validate_column_size is off (it measures the decrypted
    # value), so these explicit plaintext caps are the only thing keeping the
    # ciphertext inside its column. A too-long value must be a validation error,
    # never a ValueTooLong 500 or a silent truncation.
    test "Expense caps the encrypted override plaintext instead of overflowing the column" do
      expense = create_reimbursements_expense(receipt: false)

      expense.payee_name_override = "z" * (BankDetails::PAYEE_NAME_MAX_LENGTH + 1)
      assert_not expense.valid?
      assert expense.errors[:payee_name_override].present?

      expense.payee_name_override = "z" * BankDetails::PAYEE_NAME_MAX_LENGTH
      assert_predicate expense, :valid?
    end

    test "PaymentDetails caps the encrypted bank-detail plaintext" do
      person = create_reimbursements_person(name: "Cap Casey", email: "casey@example.com",
                                            sort_code: "08-99-99", account_number: "66374958")
      details = person.payment_details

      details.account_number = "9" * (BankDetails::BANK_DIGITS_MAX_LENGTH + 1)
      assert_not details.valid?
      assert details.errors[:account_number].present?
    end

    # The short members of the trio (and PaymentDetails' own pair) are format-
    # validated to 6/8 digits, so their ciphertext is ~82 bytes — pinned here so
    # the "verified to fit, deliberately left as string(255)" call is not an
    # assumption anyone has to re-derive.
    test "bank-detail digits encrypt well inside their string columns" do
      %w[802260 80-22-60 66374958].each do |value|
        bytes = ciphertext_bytesize(value)
        assert_operator bytes, :<, 128,
                        "#{value.inspect} encrypts to #{bytes} bytes; string(255) is still ample"
      end
    end

    # PaymentDetails#notes is the one encrypted column deliberately left uncapped:
    # it is an append-only audit trail, so a cap would eventually make a payee's
    # bank details un-editable, which is worse than the overflow it would prevent.
    # That is only defensible because the trail is highly repetitive and AR
    # Encryption compresses before encrypting, so it shrinks rather than inflates.
    # Pinned here so "TEXT has ample room" stays a measurement, not an assumption.
    test "the notes audit trail compresses far inside its TEXT column" do
      line = "[2026-07-25 14:00 UTC] Bank details updated: sort code ****2260, " \
             "account ****4958 by A Person (#1)"
      log = Array.new(1_000) { |i| line.sub("A Person (#1)", "Person #{i} (##{i})") }.join("\n")

      assert_operator log.length, :>, 65_535, "test premise: the plaintext alone overflows TEXT"
      assert_operator ciphertext_bytesize(log), :<, 65_535,
                      "1000 audit lines must still encrypt inside the TEXT column"
    end

    private

    def ciphertext_bytesize(plaintext)
      ActiveRecord::Encryption.encryptor.encrypt(
        plaintext, key_provider: ActiveRecord::Encryption.key_provider
      ).bytesize
    end
  end
end
