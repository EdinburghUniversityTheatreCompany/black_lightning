require "test_helper"

module Reimbursements
  class PaymentMailerTest < ActionMailer::TestCase
    Person = Struct.new(:name, :email, keyword_init: true)
    Expense = Struct.new(:description, :amount, :auto_number, keyword_init: true)

    def person
      Person.new(name: "Alice Producer", email: "alice@example.com")
    end

    test "payment_confirmation is addressed to the payee with a friendly subject" do
      expense = Expense.new(description: "Fake blood", amount: 12.5, auto_number: 7)

      email = PaymentMailer.payment_confirmation(person, [ expense ])

      assert_equal [ "alice@example.com" ], email.to
      assert_equal "EUSA has paid your expense", email.subject
      assert_includes email.body.encoded, "Alice Producer"
      assert_includes email.body.encoded, "Fake blood"
      # The pound sign is quoted-printable-encoded in the MIME body; assert on
      # the amount so the check is encoding-agnostic.
      assert_includes email.body.encoded, "12.50"
    end

    test "the subject pluralises for multiple expenses" do
      expenses = [ Expense.new(description: "Props", amount: 5, auto_number: 1),
                   Expense.new(description: "Set", amount: 8, auto_number: 2) ]

      email = PaymentMailer.payment_confirmation(person, expenses)

      assert_equal "EUSA has paid your expenses", email.subject
      assert_includes email.body.encoded, "Props"
      assert_includes email.body.encoded, "Set"
    end

    test "delivers nothing when the payee has no email" do
      recipient = Person.new(name: "No Email", email: "")
      expense = Expense.new(description: "Props", amount: 5, auto_number: 1)

      assert_no_difference "ActionMailer::Base.deliveries.count" do
        assert_nil PaymentMailer.payment_confirmation(recipient, [ expense ]).deliver_now
      end
    end
  end
end
