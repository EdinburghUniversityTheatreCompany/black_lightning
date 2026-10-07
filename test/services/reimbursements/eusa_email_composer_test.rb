require "test_helper"

module Reimbursements
  class EusaEmailComposerTest < ActiveSupport::TestCase
    # Built unpersisted: the composer only reads them.
    Person = Reimbursements::Person
    Budget = Reimbursements::Budget
    Expense = Reimbursements::Expense

    def cost_centre(name: "Bedlam Fringe 2026", eusa_contact_name: nil)
      CostCentre.new(key: "fringe", name: name, eusa_code: "F40",
                     receive_mailbox: "in@example.com", send_mailbox: "out@example.com",
                     eusa_contact_name: eusa_contact_name)
    end

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
                                            sender_name: "Fringe Finance", cost_centre: cost_centre,
                                            eusa_contact_name: "Sam")

      assert_equal "Bedlam Fringe 2026 BACS Request - 2026-05-13 - F40", email.subject
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
        bacs_date: Date.new(2026, 5, 13), sender_name: "F", cost_centre: cost_centre
      )
      assert_includes email.body_html, "Hi Finance Team,"
    end

    test "greets the cost centre's configured EUSA contact" do
      email = EusaEmailComposer.new.compose(
        expenses: [ expense(payee: "A", amount: "1", budget: "P", nominal: "1", description: "x") ],
        bacs_date: Date.new(2026, 5, 13), sender_name: "F",
        cost_centre: cost_centre(eusa_contact_name: "Craig")
      )
      assert_includes email.body_html, "Hi Craig,"
    end

    test "an explicit contact name overrides the cost centre's" do
      email = EusaEmailComposer.new.compose(
        expenses: [ expense(payee: "A", amount: "1", budget: "P", nominal: "1", description: "x") ],
        bacs_date: Date.new(2026, 5, 13), sender_name: "F",
        cost_centre: cost_centre(eusa_contact_name: "Craig"), eusa_contact_name: "Sam"
      )
      assert_includes email.body_html, "Hi Sam,"
      assert_not_includes email.body_html, "Craig"
    end

    # The test env renders no annotations, so the pattern is checked directly.
    test "ANNOTATION_COMMENT matches Rails' dev-mode view annotations" do
      html = "<!-- BEGIN app/views/reimbursements/emails/eusa.html.erb -->\n<p>x</p>" \
             "<!-- END app/views/reimbursements/emails/eusa.html.erb -->"

      assert_equal "<p>x</p>", html.gsub(EusaEmailComposer::ANNOTATION_COMMENT, "")
    end
  end
end
