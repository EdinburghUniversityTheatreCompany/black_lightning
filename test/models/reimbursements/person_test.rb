require "test_helper"

module Reimbursements
  class PersonTest < ActiveSupport::TestCase
    test "bank_details? requires both sort code and account number" do
      person = Person.new(record_id: "rec1", name: "Pat", email: "pat@example.com",
                          sort_code: "112233", account_number: "12345678")
      assert person.bank_details?

      assert_not Person.new(record_id: "rec1", name: "Pat", email: "pat@example.com",
                            sort_code: "112233").bank_details?
      assert_not Person.new(record_id: "rec1", name: "Pat", email: "pat@example.com").bank_details?
    end
  end
end
