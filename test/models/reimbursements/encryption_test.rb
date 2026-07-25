require "test_helper"

module Reimbursements
  # Track F: bank details are encrypted at rest. These tests prove the model
  # reads/writes plaintext transparently while the underlying DB column holds
  # ciphertext, so a DB/backup/replica dump never exposes UK bank details.
  class EncryptionTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers
    include RakeTaskTestHelpers

    # Overwrite an encrypted column with a raw PLAINTEXT value, the way every
    # row in production looked the moment the `encrypts` declarations shipped.
    # column/table are trusted literals from the test; the value is bound.
    def write_plaintext(model, id, values)
      assignments = values.keys.map { |c| "#{model.connection.quote_column_name(c)} = ?" }.join(", ")
      sql = model.sanitize_sql_array(
        [ "UPDATE #{model.table_name} SET #{assignments} WHERE id = ?", *values.values, id ]
      )
      model.connection.update(sql)
    end

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

    # --- Rollout paths (support_unencrypted_data + backfill) ---------------
    # The whole production rollout rests on one promise: rows that are STILL
    # plaintext keep reading while the backfill catches up. Nothing else in the
    # suite exercises it (every row a test writes is encrypted on the way in),
    # so flipping config.active_record.encryption.support_unencrypted_data to
    # false would stay green here and raise on every un-backfilled row's money
    # path in production.

    test "support_unencrypted_data lets a pre-existing plaintext payee row read" do
      person = create_reimbursements_person(name: "Legacy Len", email: "len@example.com",
                                           sort_code: "20-20-20", account_number: "50502366",
                                           notes: "pre-rollout note")
      details = person.payment_details
      write_plaintext(PaymentDetails, details.id,
                      sort_code: "08-99-99", account_number: "66374958",
                      notes: "Bank details updated: account ****4958")

      # Sanity: the row really is plaintext on disk now, as it was pre-rollout.
      assert_equal "66374958", raw_column(PaymentDetails, details.id, "account_number")

      reread = PaymentDetails.find(details.id)
      assert_equal "08-99-99", reread.sort_code
      assert_equal "66374958", reread.account_number
      assert_equal "Bank details updated: account ****4958", reread.notes
      # The BACS spreadsheet and the modulus check read through these.
      assert_equal "66374958", reread.person.account_number
    end

    test "support_unencrypted_data lets a pre-existing plaintext override trio read" do
      expense = create_reimbursements_expense(receipt: false, payee_name_override: "Encrypted Ltd",
                                              sort_code_override: "20-20-20",
                                              account_number_override: "50502366")
      write_plaintext(Expense, expense.id,
                      payee_name_override: "Legacy Payee Ltd",
                      sort_code_override: "08-99-99", account_number_override: "66374958")

      reread = Expense.find(expense.id)
      assert_equal "Legacy Payee Ltd", reread.payee_name_override
      assert_equal "08-99-99", reread.sort_code_override
      assert_equal "66374958", reread.account_number_override
      # effective_* is what the BACS builder actually pays against.
      assert_equal "66374958", reread.effective_account_number
    end

    test "the backfill task rewrites a plaintext row as ciphertext" do
      person = create_reimbursements_person(name: "Legacy Len", email: "len@example.com",
                                           sort_code: "20-20-20", account_number: "50502366")
      details = person.payment_details
      write_plaintext(PaymentDetails, details.id,
                      sort_code: "08-99-99", account_number: "66374958")

      run_rake_task("reimbursements:encrypt_backfill")

      raw = raw_column(PaymentDetails, details.id, "account_number")
      assert_not_equal "66374958", raw, "the backfill must leave ciphertext behind"
      assert_not_includes raw.to_s, "66374958"
      # And it is still the same value to the application.
      assert_equal "66374958", PaymentDetails.find(details.id).account_number
      assert_equal "08-99-99", PaymentDetails.find(details.id).sort_code
    end

    test "the backfill task also encrypts a plaintext expense override trio" do
      expense = create_reimbursements_expense(receipt: false, payee_name_override: "Encrypted Ltd",
                                              account_number_override: "50502366")
      write_plaintext(Expense, expense.id,
                      payee_name_override: "Legacy Payee Ltd", account_number_override: "66374958")

      run_rake_task("reimbursements:encrypt_backfill")

      assert_not_includes raw_column(Expense, expense.id, "account_number_override").to_s, "66374958"
      assert_not_includes raw_column(Expense, expense.id, "payee_name_override").to_s, "Legacy Payee"
      assert_equal "66374958", Expense.find(expense.id).account_number_override
      assert_equal "Legacy Payee Ltd", Expense.find(expense.id).payee_name_override
    end

    # Re-running after a partial run must not fail (an operator WILL re-run it),
    # and the values must survive the second pass intact.
    test "the backfill task is safe to run twice" do
      person = create_reimbursements_person(name: "Legacy Len", email: "len@example.com",
                                           account_number: "50502366")
      details = person.payment_details
      write_plaintext(PaymentDetails, details.id, account_number: "66374958")

      output = run_rake_task("reimbursements:encrypt_backfill")
      second = run_rake_task("reimbursements:encrypt_backfill")

      assert_match(/processed 1\/1/, output)
      assert_no_match(/failed/, second, "a re-run must report no failures")
      assert_equal "66374958", PaymentDetails.find(details.id).account_number
      assert_not_includes raw_column(PaymentDetails, details.id, "account_number").to_s, "66374958"
    end
  end
end
