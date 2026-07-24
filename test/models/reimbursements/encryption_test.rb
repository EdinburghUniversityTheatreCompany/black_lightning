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
  end
end
