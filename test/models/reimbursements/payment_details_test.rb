require "test_helper"

module Reimbursements
  class PaymentDetailsTest < ActiveSupport::TestCase
    # PaymentDetails::FIELDS is the operator-writable vocabulary, and
    # DatabaseStore#update_person! slices incoming attributes with it: a bank field missing
    # from the list is silently dropped instead of saved. Pinning it to the actual columns
    # means adding a column fails here until the vocabulary knows about it.
    test "FIELDS covers every writable column of the table" do
      bookkeeping = %w[id person_id created_at updated_at]
      writable = PaymentDetails.column_names - bookkeeping

      assert_equal writable.sort, PaymentDetails::FIELDS.map(&:to_s).sort
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

    test "bank_details? needs both halves" do
      person = Person.create!(name: "Pat", email: "pat-both@example.com")
      details = person.create_payment_details!(sort_code: "80-22-60", account_number: "")

      assert_not details.bank_details?

      details.update!(account_number: "12345678")
      assert details.bank_details?
    end
  end
end
