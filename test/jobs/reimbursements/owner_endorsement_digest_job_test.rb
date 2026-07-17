require "test_helper"

module Reimbursements
  class OwnerEndorsementDigestJobTest < ActiveJob::TestCase
    include ReimbursementsTestHelpers

    setup do
      # The owning person shares an email with a real portal user, so they can
      # be nudged; the submitter is a different, account-less person.
      @owner_user = users(:member)
      @owner = airtable_person_record(id: "recOwner", name: "Olga Owner", email: @owner_user.email)
      @submitter = airtable_person_record(id: "recSub", name: "Sam Sub", email: "sam@example.com")
      @budget = airtable_budget_record(id: "recBud1", name: "Props", owner_ids: [ "recOwner" ])
      @awaiting = airtable_expense_record(id: "recExp1", payee_id: "recSub", budget_id: "recBud1",
                                          status: "Pending", description: "Van hire")
    end

    teardown { OwnerEndorsementDigestJob.store_builder = -> { Store.new } }

    def use_store(expenses:, people: nil, budgets: nil)
      store, _client = build_fake_store(
        expenses: expenses, people: people || [ @owner, @submitter ], budgets: budgets || [ @budget ]
      )
      OwnerEndorsementDigestJob.store_builder = -> { store }
    end

    test "emails an owner with a portal account about a pending claim awaiting their sign-off" do
      use_store(expenses: [ @awaiting ])

      assert_emails(1) { OwnerEndorsementDigestJob.perform_now }
    end

    test "sends nothing when no pending claim awaits endorsement" do
      use_store(expenses: [])

      assert_no_emails { OwnerEndorsementDigestJob.perform_now }
    end

    test "does not email an owner who has no portal account" do
      # The only owner's email matches no User, so they can't endorse — the
      # finance override covers them and no digest is sent.
      accountless = airtable_person_record(id: "recOwner", name: "Olga", email: "nouser@example.com")
      use_store(expenses: [ @awaiting ], people: [ accountless, @submitter ])

      assert_no_emails { OwnerEndorsementDigestJob.perform_now }
    end

    test "does not email about a claim the owner already endorsed" do
      # airtable_expense_record's default amount (12.5) is what @awaiting carries.
      OwnerEndorsement.create!(expense_record_id: "recExp1", budget_record_id: "recBud1",
                               endorsed_by_person_id: "recOwner", endorsed_amount: BigDecimal("12.5"),
                               endorsed_at: Time.current)
      use_store(expenses: [ @awaiting ])

      assert_no_emails { OwnerEndorsementDigestJob.perform_now }
    end

    test "does not email about a claim the owner submitted themselves (auto-bypass)" do
      own = airtable_expense_record(id: "recExp2", payee_id: "recOwner", budget_id: "recBud1",
                                    status: "Pending", description: "Owner's own claim")
      use_store(expenses: [ own ])

      assert_no_emails { OwnerEndorsementDigestJob.perform_now }
    end

    test "the digest renders without error and names the claim" do
      use_store(expenses: [ @awaiting ])

      assert_emails(1) { OwnerEndorsementDigestJob.perform_now }

      email = ActionMailer::Base.deliveries.last
      assert_not_nil email
      assert_equal [ @owner_user.email ], email.to
      assert_match(/Van hire/, email.body.encoded)
    end

    test "nudges every account-holding owner of a shared budget (any one can act)" do
      second_user = users(:admin)
      second_owner = airtable_person_record(id: "recOwner2", name: "Otto Owner", email: second_user.email)
      shared = airtable_budget_record(id: "recBud1", name: "Props", owner_ids: %w[recOwner recOwner2])
      use_store(expenses: [ @awaiting ], people: [ @owner, second_owner, @submitter ], budgets: [ shared ])

      assert_emails(2) { OwnerEndorsementDigestJob.perform_now }
      recipients = ActionMailer::Base.deliveries.last(2).flat_map(&:to)
      assert_includes recipients, @owner_user.email
      assert_includes recipients, second_user.email
    end

    test "resolves an owner by the stored airtable_person_id link when emails differ" do
      # The owner's People email doesn't match their portal account's email, but
      # the durable PersonLink (User#airtable_person_id) still resolves them.
      @owner_user.update_column(:airtable_person_id, "recOwner")
      drifted = airtable_person_record(id: "recOwner", name: "Olga", email: "different-people-email@example.com")
      use_store(expenses: [ @awaiting ], people: [ drifted, @submitter ])

      assert_emails(1) { OwnerEndorsementDigestJob.perform_now }
      assert_equal [ @owner_user.email ], ActionMailer::Base.deliveries.last.to
    end
  end
end
