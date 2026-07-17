require "test_helper"

module Reimbursements
  class OwnerEndorsementDigestJobTest < ActiveJob::TestCase
    include ReimbursementsTestHelpers

    setup do
      # The owning person shares an email with a real portal user, so they can
      # be nudged; the submitter is a different, account-less person.
      @owner_user = users(:member)
      @owner = create_reimbursements_person(name: "Olga Owner", email: @owner_user.email)
      @submitter = create_reimbursements_person(name: "Sam Sub", email: "sam@example.com")
      @budget = create_reimbursements_budget(name: "Props", owners: [ @owner ])
    end

    def awaiting_expense(**attrs)
      create_reimbursements_expense(person: @submitter, budget: @budget, status: Status::PENDING,
                                    description: "Van hire", **attrs)
    end

    test "emails an owner with a portal account about a pending claim awaiting their sign-off" do
      awaiting_expense

      assert_emails(1) { OwnerEndorsementDigestJob.perform_now }
    end

    test "sends nothing when no pending claim awaits endorsement" do
      assert_no_emails { OwnerEndorsementDigestJob.perform_now }
    end

    test "does not email an owner who has no portal account" do
      # The only owner's email matches no User, so they can't endorse — the
      # finance override covers them and no digest is sent.
      accountless = create_reimbursements_person(name: "Olga", email: "nouser@example.com")
      @budget.budget_ownerships.destroy_all
      @budget.owners << accountless
      awaiting_expense

      assert_no_emails { OwnerEndorsementDigestJob.perform_now }
    end

    test "does not email about a claim the owner already endorsed" do
      expense = awaiting_expense
      OwnerEndorsement.create!(expense_record_id: expense.record_id,
                               budget_record_id: @budget.record_id,
                               endorsed_by_person_id: @owner.record_id,
                               endorsed_amount: BigDecimal("12.5"),
                               endorsed_at: Time.current)

      assert_no_emails { OwnerEndorsementDigestJob.perform_now }
    end

    test "does not email about a claim the owner submitted themselves (auto-bypass)" do
      create_reimbursements_expense(person: @owner, budget: @budget, status: Status::PENDING,
                                    description: "Owner's own claim")

      assert_no_emails { OwnerEndorsementDigestJob.perform_now }
    end

    test "the digest renders without error and names the claim" do
      awaiting_expense

      assert_emails(1) { OwnerEndorsementDigestJob.perform_now }

      email = ActionMailer::Base.deliveries.last
      assert_not_nil email
      assert_equal [ @owner_user.email ], email.to
      assert_match(/Van hire/, email.body.encoded)
    end

    test "nudges every account-holding owner of a shared budget (any one can act)" do
      second_user = users(:admin)
      second_owner = create_reimbursements_person(name: "Otto Owner", email: second_user.email)
      @budget.owners << second_owner
      awaiting_expense

      assert_emails(2) { OwnerEndorsementDigestJob.perform_now }
      recipients = ActionMailer::Base.deliveries.last(2).flat_map(&:to)
      assert_includes recipients, @owner_user.email
      assert_includes recipients, second_user.email
    end

    test "resolves an owner by the stored person link when emails differ" do
      # The owner's People email doesn't match their portal account's email, but
      # the durable PersonLink (users.reimbursements_person_id on this backend)
      # still resolves them.
      @owner.update!(email: "different-people-email@example.com")
      @owner_user.update_column(:reimbursements_person_id, @owner.id)
      awaiting_expense

      assert_emails(1) { OwnerEndorsementDigestJob.perform_now }
      assert_equal [ @owner_user.email ], ActionMailer::Base.deliveries.last.to
    end
  end
end
