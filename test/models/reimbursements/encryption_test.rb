require "test_helper"

module Reimbursements
  # Bank details read as plaintext through the model while the DB column holds
  # ciphertext, so a dump or replica never exposes them.
  class EncryptionTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers
    include RakeTaskTestHelpers

    # Overwrites an encrypted column with raw PLAINTEXT, as every row looked when
    # `encrypts` first shipped.
    def write_plaintext(model, id, values)
      assignments = values.keys.map { |c| "#{model.connection.quote_column_name(c)} = ?" }.join(", ")
      sql = model.sanitize_sql_array(
        [ "UPDATE #{model.table_name} SET #{assignments} WHERE id = ?", *values.values, id ]
      )
      model.connection.update(sql)
    end

    # The bytes stored in the column, bypassing decryption: what a dump would reveal.
    def raw_column(model, id, column)
      quoted_column = model.connection.quote_column_name(column)
      sql = model.sanitize_sql_array(
        [ "SELECT #{quoted_column} FROM #{model.table_name} WHERE id = ?", id ]
      )
      model.connection.select_value(sql)
    end

    test "bank details are encrypted at rest" do
      details = create_reimbursements_person(
        name: "Cipher Cassie", email: "cassie@example.com",
        sort_code: "08-99-99", account_number: "66374958",
        notes: "Bank details updated: account ****4958"
      ).payment_details
      expense = create_reimbursements_expense(
        receipt: false, payee_name_override: "Third Party Ltd",
        sort_code_override: "20-20-20", account_number_override: "50502366"
      )

      {
        details => { sort_code: "08-99-99", account_number: "66374958",
                     notes: "Bank details updated: account ****4958" },
        expense => { payee_name_override: "Third Party Ltd", sort_code_override: "20-20-20",
                     account_number_override: "50502366" }
      }.each do |record, columns|
        columns.each do |column, value|
          assert_equal value, record.public_send(column)
          assert_not_includes raw_column(record.class, record.id, column).to_s, value,
                              "#{record.class.name}##{column} must not be stored in plaintext"
        end
      end
    end

    # Encryption inflates the value: any low-redundancy plaintext of ~124+ characters
    # exceeds 255 bytes (255 characters lands at ~394). validate_column_size measures
    # the DECRYPTED length so cannot catch it: strict MySQL raises ValueTooLong, a
    # non-strict server truncates the ciphertext into garbage that would reach the
    # BACS spreadsheet as a payee name. payee_name_override is the only free-text
    # member of the override trio.
    test "Expense round-trips a payee name override whose ciphertext exceeds 255 bytes" do
      # Low-redundancy so compression can't shrink it back under 255 bytes.
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

    # validate_column_size is off, so these explicit plaintext caps are all that
    # keeps the ciphertext in its column: too long must be a validation error.
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

    # Format-validated digits encrypt to ~82 bytes: pins that string(255) is ample.
    test "bank-detail digits encrypt well inside their string columns" do
      %w[802260 80-22-60 66374958].each do |value|
        bytes = ciphertext_bytesize(value)
        assert_operator bytes, :<, 128,
                        "#{value.inspect} encrypts to #{bytes} bytes; string(255) is still ample"
      end
    end

    # `notes` is deliberately uncapped (a cap would eventually make a payee's details
    # un-editable). Safe only because the trail is repetitive and AR Encryption
    # compresses before encrypting; this pins that as a measurement.
    test "the notes audit trail compresses far inside its TEXT column" do
      line = "[2026-07-25 14:00 UTC] Bank details updated: sort code ****2260, " \
             "account ****4958 by A Person (#1)"
      log = Array.new(1_000) { |i| line.sub("A Person (#1)", "Person #{i} (##{i})") }.join("\n")

      assert_operator log.length, :>, 65_535, "test premise: the plaintext alone overflows TEXT"
      assert_operator ciphertext_bytesize(log), :<, 65_535,
                      "1000 audit lines must still encrypt inside the TEXT column"
    end

    # Reading plaintext is off everywhere now, but encrypting a new column later
    # repeats the rollout (flag on, backfill, flag off), so these tests opt in for
    # their own duration rather than relying on a global that no longer matches production.
    def with_unencrypted_data_support
      previous = ActiveRecord::Encryption.config.support_unencrypted_data
      ActiveRecord::Encryption.config.support_unencrypted_data = true
      yield
    ensure
      ActiveRecord::Encryption.config.support_unencrypted_data = previous
    end

    # Without the opt-in, a plaintext row is a hard error on the money path, not a silent read.
    test "a plaintext row raises once support_unencrypted_data is off" do
      person = create_reimbursements_person(name: "Legacy Len", email: "len@example.com",
                                           sort_code: "20-20-20", account_number: "50502366")
      details = person.payment_details
      write_plaintext(PaymentDetails, details.id, account_number: "66374958")

      assert_raises(ActiveRecord::Encryption::Errors::Decryption) do
        PaymentDetails.find(details.id).account_number
      end
    end

    # An operator WILL re-run it after a partial run.
    test "the backfill task encrypts plaintext rows and is safe to re-run" do
      with_unencrypted_data_support do
        details = create_reimbursements_person(name: "Legacy Len", email: "len@example.com",
                                               sort_code: "20-20-20", account_number: "50502366").payment_details
        expense = create_reimbursements_expense(receipt: false, payee_name_override: "Encrypted Ltd",
                                                account_number_override: "50502366")
        write_plaintext(PaymentDetails, details.id, sort_code: "08-99-99", account_number: "66374958")
        write_plaintext(Expense, expense.id,
                        payee_name_override: "Legacy Payee Ltd", account_number_override: "66374958")

        assert_match(/PaymentDetails: processed 1\/1/, run_rake_task("reimbursements:encrypt_backfill"))
        assert_no_match(/failed/, run_rake_task("reimbursements:encrypt_backfill"), "a re-run must report no failures")

        assert_not_includes raw_column(PaymentDetails, details.id, "account_number").to_s, "66374958"
        assert_not_includes raw_column(Expense, expense.id, "account_number_override").to_s, "66374958"
        assert_not_includes raw_column(Expense, expense.id, "payee_name_override").to_s, "Legacy Payee"
        assert_equal "08-99-99", PaymentDetails.find(details.id).sort_code
        assert_equal "66374958", PaymentDetails.find(details.id).account_number
        assert_equal "66374958", Expense.find(expense.id).account_number_override
        assert_equal "Legacy Payee Ltd", Expense.find(expense.id).payee_name_override
      end
    end

    # Deliberately NOT wrapped in with_unencrypted_data_support: the flag being off
    # (the production state) is the condition under test.
    test "the backfill task refuses to run while support_unencrypted_data is off" do
      assert_not ActiveRecord::Encryption.config.support_unencrypted_data,
                 "test premise: the flag is off by default now that the rollout is closed"

      create_reimbursements_person(name: "Payee Pat", email: "pat@example.com",
                                   sort_code: "20-20-20", account_number: "50502366")
      error = assert_raises(SystemExit) do
        run_rake_task("reimbursements:encrypt_backfill")
      end

      assert_not_predicate error, :success?
      assert_match(/support_unencrypted_data/, error.message,
                   "the refusal has to name the flag that has to change")
      # Bailed before touching a row, rather than failing each one.
      assert_no_match(/Encrypting/, last_rake_output)
    end

    private

    def ciphertext_bytesize(plaintext)
      ActiveRecord::Encryption.encryptor.encrypt(
        plaintext, key_provider: ActiveRecord::Encryption.key_provider
      ).bytesize
    end
  end
end
