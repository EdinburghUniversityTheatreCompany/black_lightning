require "test_helper"

module Reimbursements
  class OwnerReviewTest < ActiveSupport::TestCase
    # Until the DB-backed test migration, these tests exercise the Airtable
    # boundary POROs the Mapper builds.
    Person = Airtable::Person
    Budget = Airtable::Budget
    Expense = Airtable::Expense

    def person(id: "recPer1", name: "Alice", email: "alice@example.com")
      Person.new(record_id: id, name: name, email: email)
    end

    def budget(id: "recBud1", owner_ids: [])
      Budget.new(record_id: id, name: "Props", owner_ids: owner_ids)
    end

    def expense(budget:, submitter:, id: "recExp1", amount: BigDecimal("10"))
      Expense.new(record_id: id, auto_number: 1, status: Status::PENDING,
                  person: submitter, amount: amount, budget: budget,
                  description: "x", receipts: [])
    end

    test "owned_budgets returns only budgets the person owns" do
      alice = person
      owned = budget(id: "recBud1", owner_ids: [ "recPer1" ])
      other = budget(id: "recBud2", owner_ids: [ "recPer9" ])
      assert_equal [ owned ], OwnerReview.owned_budgets([ owned, other ], alice)
    end

    test "owned_budgets is empty for a nil person" do
      assert_empty OwnerReview.owned_budgets([ budget(owner_ids: [ "recPer1" ]) ], nil)
    end

    test "gate applies to an expense on an owned budget submitted by a non-owner" do
      exp = expense(budget: budget(owner_ids: [ "recPer1" ]), submitter: person(id: "recPerOther"))
      assert OwnerReview.gate_applies?(exp)
    end

    test "gate does not apply when the submitter owns the budget (auto-bypass)" do
      alice = person(id: "recPer1")
      exp = expense(budget: budget(owner_ids: [ "recPer1" ]), submitter: alice)
      assert_not OwnerReview.gate_applies?(exp)
      assert OwnerReview.submitter_owns_budget?(exp)
    end

    test "gate does not apply to an ownerless budget" do
      exp = expense(budget: budget(owner_ids: []), submitter: person(id: "recPerOther"))
      assert_not OwnerReview.gate_applies?(exp)
    end

    test "gate_satisfied? is true once an endorsement covers the current terms" do
      exp = expense(budget: budget(owner_ids: [ "recPer1" ]), submitter: person(id: "recPerOther"))
      assert_not OwnerReview.gate_satisfied?(exp)

      OwnerEndorsement.create!(expense_record_id: exp.record_id, budget_record_id: "recBud1",
                               endorsed_by_person_id: "recPer1", endorsed_amount: BigDecimal("10"),
                               endorsed_at: Time.current)
      assert OwnerReview.gate_satisfied?(exp)
    end

    test "an endorsement no longer covers the claim once its amount is edited" do
      # Alice endorses a £10 claim; it's then bumped to £2000. The stale sign-off
      # must NOT keep clearing the gate for the new, higher amount.
      OwnerEndorsement.create!(expense_record_id: "recExp1", budget_record_id: "recBud1",
                               endorsed_by_person_id: "recPer1", endorsed_amount: BigDecimal("10"),
                               endorsed_at: Time.current)
      edited = expense(budget: budget(owner_ids: [ "recPer1" ]), submitter: person(id: "recPerOther"),
                       id: "recExp1", amount: BigDecimal("2000"))
      assert_not OwnerReview.gate_satisfied?(edited)
    end

    test "an endorsement no longer covers the claim once its budget is reassigned" do
      OwnerEndorsement.create!(expense_record_id: "recExp1", budget_record_id: "recBudOld",
                               endorsed_by_person_id: "recPer1", endorsed_amount: BigDecimal("10"),
                               endorsed_at: Time.current)
      moved = expense(budget: budget(id: "recBudNew", owner_ids: [ "recPer1" ]),
                      submitter: person(id: "recPerOther"), id: "recExp1")
      assert_not OwnerReview.gate_satisfied?(moved)
    end

    test "gate_satisfied? is true for a bypassed expense with no endorsement row" do
      exp = expense(budget: budget(owner_ids: [ "recPer1" ]), submitter: person(id: "recPer1"))
      assert OwnerReview.gate_satisfied?(exp)
    end

    test "owned_by? checks the expense's budget owners" do
      exp = expense(budget: budget(owner_ids: [ "recPer1" ]), submitter: person(id: "recPerOther"))
      assert OwnerReview.owned_by?(exp, person(id: "recPer1"))
      assert_not OwnerReview.owned_by?(exp, person(id: "recPer2"))
    end
  end
end
