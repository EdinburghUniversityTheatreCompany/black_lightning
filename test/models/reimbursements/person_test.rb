require "test_helper"

module Reimbursements
  # The AR Person must keep the Airtable-era PORO's flat bank-detail
  # interface (delegated to the one-to-one PaymentDetails record).
  class PersonTest < ActiveSupport::TestCase
    test "record_id is the string id" do
      person = Person.create!(name: "Pat", email: "pat@example.com")
      assert_equal person.id.to_s, person.record_id
    end

    test "bank detail readers keep PORO defaults without a payment_details row" do
      person = Person.create!(name: "Pat", email: "pat2@example.com")
      assert_equal "", person.sort_code
      assert_equal "", person.account_number
      assert_equal "", person.notes
      assert_not person.verified
      assert_not person.bank_details?
    end

    test "bank detail readers delegate to payment_details" do
      person = Person.create!(name: "Pat", email: "pat3@example.com")
      person.create_payment_details!(sort_code: "80-22-60", account_number: "12345678",
                                     verified: true, notes: "checked")
      assert_equal "80-22-60", person.sort_code
      assert_equal "12345678", person.account_number
      assert_equal "checked", person.notes
      assert person.verified?
      assert person.bank_details?
    end

    test "blank email is stored as NULL so many payees may lack one" do
      a = Person.create!(name: "A", email: "")
      b = Person.create!(name: "B", email: "   ")
      assert_nil a.reload.email
      assert_nil b.reload.email
    end

    test "email is unique case-insensitively" do
      Person.create!(name: "A", email: "dupe@example.com")
      dupe = Person.new(name: "B", email: "DUPE@example.com")
      assert_not dupe.valid?
      assert dupe.errors[:email].present?
    end
  end
end
