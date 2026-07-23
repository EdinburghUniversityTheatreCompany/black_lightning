require "test_helper"

module Reimbursements
  class EusaEmailComposerTest < ActiveSupport::TestCase
    # The composer reads the AR models' public interface (effective payee name,
    # nominal code, amount, description); built unpersisted.
    Person = Reimbursements::Person
    Budget = Reimbursements::Budget
    Expense = Reimbursements::Expense

    def expense(payee:, amount:, budget:, nominal:, description:)
      person = Person.new(name: payee, email: "#{payee}@x")
      budget_obj = Budget.new(name: budget, nominal_code: nominal)
      Expense.new(status: Status::APPROVED, person: person, budget: budget_obj,
                  amount: BigDecimal(amount.to_s), description: description)
    end

    test "composes the subject with the date and cost centre and a totalled table" do
      expenses = [
        expense(payee: "Alice", amount: "12.50", budget: "Props", nominal: "4000", description: "Blood"),
        expense(payee: "Bob", amount: "100", budget: "Set", nominal: "4100", description: "Timber")
      ]

      email = EusaEmailComposer.new.compose(expenses: expenses, bacs_date: Date.new(2026, 5, 13),
                                            sender_name: "Fringe Finance", eusa_code: "F40",
                                            eusa_contact_name: "Sam")

      assert_equal "Bedlam Fringe BACS Request - 2026-05-13 - F40", email.subject
      assert_includes email.body_html, "Hi Sam,"
      assert_includes email.body_html, "totalling"
      assert_includes email.body_html, "112.50" # rounded total of 12.50 + 100
      assert_includes email.body_html, "Alice"
      assert_includes email.body_html, "Timber"
      assert_includes email.body_html, "Fringe Finance"
    end

    test "falls back to a generic greeting without a named contact" do
      email = EusaEmailComposer.new.compose(
        expenses: [ expense(payee: "A", amount: "1", budget: "P", nominal: "1", description: "x") ],
        bacs_date: Date.new(2026, 5, 13), sender_name: "F", eusa_code: "F40"
      )
      assert_includes email.body_html, "Hi Finance Team,"
    end

    test "strips dev-mode view-annotation comments from the body" do
      email = EusaEmailComposer.new.compose(
        expenses: [ expense(payee: "A", amount: "1", budget: "P", nominal: "1", description: "x") ],
        bacs_date: Date.new(2026, 5, 13), sender_name: "F", eusa_code: "F40"
      )
      assert_not_includes email.body_html, "BEGIN app/views",
                          "Rails view-annotation comments must never reach the EUSA draft"
      assert_not_includes email.body_html, ".erb -->"
    end
  end
end
