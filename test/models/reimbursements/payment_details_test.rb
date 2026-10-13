require "test_helper"

module Reimbursements
  class PaymentDetailsTest < ActiveSupport::TestCase
    # DatabaseStore#update_person! slices attributes with FIELDS, so a column missing
    # from it is silently dropped; this fails until the list knows about a new column.
    test "FIELDS covers every writable column of the table" do
      bookkeeping = %w[id person_id created_at updated_at]
      writable = PaymentDetails.column_names - bookkeeping

      assert_equal writable.sort, PaymentDetails::FIELDS.map(&:to_s).sort
    end

    # BankDetailsRetention clears only the UK pair, so a payee-level IBAN would outlive it.
    test "a payee holds no IBAN or BIC: an international claim carries its own" do
      assert_not_includes PaymentDetails.column_names, "iban"
      assert_not_includes PaymentDetails.column_names, "bic"
      assert_raises(ActiveModel::UnknownAttributeError) { PaymentDetails.new(iban: "DE89370400440532013000") }
    end

    test "the store writes every field in the vocabulary through to the record" do
      person = Person.create!(name: "Pat", email: "pat-fields@example.com")

      DatabaseStore.new.update_person!(person.record_id, sort_code: "80-22-60",
                                                        account_number: "12345678",
                                                        verified: true, notes: "checked")

      details = person.reload.payment_details
      assert_equal "80-22-60", details.sort_code
      assert_equal "12345678", details.account_number
      assert_equal "checked", details.notes
      assert details.verified
    end
  end
end
