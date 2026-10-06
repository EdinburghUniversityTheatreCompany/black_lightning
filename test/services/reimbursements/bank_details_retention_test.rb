require "test_helper"

module Reimbursements
  ##
  # Details are kept while there is a claim to pay and cleared after a while
  # without one. The Person and their expenses are never touched.
  class BankDetailsRetentionTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    LONG_AGO = 8.months
    RECENTLY = 2.months

    def payee(name:, email:, **attrs)
      create_reimbursements_person(name: name, email: email, sort_code: "08-99-99",
                                   account_number: "66374958", **attrs)
    end

    # The details' own age is the clock when there are no claims.
    def backdate!(person, ago)
      person.payment_details.update_columns(created_at: ago.ago, updated_at: ago.ago)
      person
    end

    def claim(person, status:, ago: RECENTLY)
      expense = create_reimbursements_expense(person: person, status: status)
      expense.update_columns(created_at: ago.ago, updated_at: ago.ago)
      expense
    end

    test "clears the details of a payee whose last claim is past the retention period" do
      person = backdate!(payee(name: "Dormant Dora", email: "dora@example.com"), LONG_AGO)
      claim(person, status: Status::PAID, ago: LONG_AGO)

      assert_equal 1, BankDetailsRetention.erase_stale!

      details = person.reload.payment_details
      assert_equal "", details.sort_code
      assert_equal "", details.account_number
      assert_not details.verified
    end

    test "keeps the details of a payee who claimed inside the retention period" do
      person = backdate!(payee(name: "Active Alex", email: "alex@example.com"), LONG_AGO)
      claim(person, status: Status::PAID, ago: RECENTLY)

      assert_equal 0, BankDetailsRetention.erase_stale!
      assert_equal "66374958", person.reload.account_number
    end

    # Age is irrelevant while a claim can still be paid into that account.
    (Status.all - [ Status::PAID, Status::REJECTED ]).each do |status|
      test "never clears details while a #{status} claim is outstanding, however old" do
        person = backdate!(payee(name: "Waiting Wren #{status}", email: "wren-#{status}@example.com"), LONG_AGO)
        claim(person, status: status, ago: LONG_AGO)

        assert_equal 0, BankDetailsRetention.erase_stale!
        assert_equal "66374958", person.reload.account_number
      end
    end

    # Wrongly reading a claim as finished wipes details irreversibly; wrongly
    # reading one as live only keeps them longer. So an unrecognised status
    # (update_column and legacy rows bypass the inclusion validation) must block.
    test "an unrecognised status blocks clearing rather than being waved through" do
      person = backdate!(payee(name: "Legacy Lou", email: "lou@example.com"), LONG_AGO)
      expense = claim(person, status: Status::PAID, ago: LONG_AGO)
      expense.update_column(:status, "Awaiting Treasurer")

      assert_equal 0, BankDetailsRetention.erase_stale!
      assert_equal "66374958", person.reload.account_number
    end

    test "a rejected claim does not keep details alive" do
      person = backdate!(payee(name: "Rejected Rae", email: "rae@example.com"), LONG_AGO)
      claim(person, status: Status::REJECTED, ago: LONG_AGO)

      assert_equal 1, BankDetailsRetention.erase_stale!
      assert_equal "", person.reload.account_number
    end

    test "clears details that were entered and never used" do
      person = backdate!(payee(name: "Never Nell", email: "nell@example.com"), LONG_AGO)

      assert_equal 1, BankDetailsRetention.erase_stale!
      assert_equal "", person.reload.account_number
    end

    test "leaves freshly entered details alone even with no claims yet" do
      payee(name: "New Nina", email: "nina@example.com")

      assert_equal 0, BankDetailsRetention.erase_stale!
    end

    # Re-verifying details is activity in its own right.
    test "recently touched details survive an old claim" do
      person = payee(name: "Rechecked Ravi", email: "ravi@example.com")
      claim(person, status: Status::PAID, ago: LONG_AGO)

      assert_equal 0, BankDetailsRetention.erase_stale!
      assert_equal "66374958", person.reload.account_number
    end

    test "owning a budget is not a reason to keep bank details" do
      person = backdate!(payee(name: "Owner Ozzy", email: "ozzy@example.com"), LONG_AGO)
      create_reimbursements_budget(name: "Ozzy's budget", owners: [ person ])

      assert_equal 1, BankDetailsRetention.erase_stale!
      assert_equal "", person.reload.account_number
    end

    test "the clearing is recorded in the audit trail, without the digits" do
      person = backdate!(payee(name: "Dormant Dora", email: "dora2@example.com",
                               notes: "[2026-01-01 09:00 UTC] Bank details updated: account ****4958"), LONG_AGO)

      BankDetailsRetention.erase_stale!

      notes = person.reload.notes
      assert_match(/Bank details cleared/, notes)
      assert_match(/6 months/, notes)
      assert_match(/account \*\*\*\*4958/, notes, "the earlier audit trail is kept — it is the record of processing")
      assert_not_includes notes.sub("****4958", ""), "4958", "the cleared value itself is not written down"
    end

    # Nothing but the account details goes.
    test "the payee and their claims are left untouched" do
      person = backdate!(payee(name: "Dormant Dora", email: "dora3@example.com"), LONG_AGO)
      expense = claim(person, status: Status::PAID, ago: LONG_AGO)

      BankDetailsRetention.erase_stale!

      assert Person.exists?(person.id)
      assert_equal "Dormant Dora", person.reload.name
      assert_equal person.id, expense.reload.person_id
    end

    test "a payee with no details on file is not counted as cleared" do
      create_reimbursements_person(name: "No Details Ned", email: "ned@example.com")

      assert_equal 0, BankDetailsRetention.erase_stale!
    end

    test "running twice clears nothing the second time" do
      person = backdate!(payee(name: "Dormant Dora", email: "dora4@example.com"), LONG_AGO)
      claim(person, status: Status::PAID, ago: LONG_AGO)

      assert_equal 1, BankDetailsRetention.erase_stale!
      assert_equal 0, BankDetailsRetention.erase_stale!
    end
  end
end
