require "test_helper"

module Reimbursements
  class OwnerEndorsementTest < ActiveSupport::TestCase
    test "a valid owner endorsement records the endorsing person" do
      endorsement = OwnerEndorsement.new(expense_record_id: "recExp1", budget_record_id: "recBud1",
                                         endorsed_by_person_id: "recPer1", endorsed_at: Time.current)
      assert endorsement.valid?
      assert endorsement.owner_endorsement?
      assert_not endorsement.finance_override?
    end

    test "a valid finance override records the overriding user, not a person" do
      user = users(:admin)
      endorsement = OwnerEndorsement.new(expense_record_id: "recExp1", budget_record_id: "recBud1",
                                         overridden_by: user, note: "no owner has an account",
                                         endorsed_at: Time.current)
      assert endorsement.valid?
      assert endorsement.finance_override?
      assert_not endorsement.owner_endorsement?
    end

    test "requires either an endorsing owner or an override, not neither" do
      endorsement = OwnerEndorsement.new(expense_record_id: "recExp1", budget_record_id: "recBud1",
                                         endorsed_at: Time.current)
      assert_not endorsement.valid?
      assert endorsement.errors[:base].present?
    end

    test "rejects being both an owner endorsement and an override" do
      endorsement = OwnerEndorsement.new(expense_record_id: "recExp1", budget_record_id: "recBud1",
                                         endorsed_by_person_id: "recPer1", overridden_by: users(:admin),
                                         endorsed_at: Time.current)
      assert_not endorsement.valid?
      assert endorsement.errors[:base].present?
    end

    test "expense_record_id, budget_record_id and endorsed_at are required" do
      endorsement = OwnerEndorsement.new(endorsed_by_person_id: "recPer1")
      assert_not endorsement.valid?
      assert endorsement.errors[:expense_record_id].present?
      assert endorsement.errors[:budget_record_id].present?
      assert endorsement.errors[:endorsed_at].present?
    end

    test "only one endorsement can exist per expense (any one owner suffices)" do
      OwnerEndorsement.create!(expense_record_id: "recExp1", budget_record_id: "recBud1",
                               endorsed_by_person_id: "recPer1", endorsed_at: Time.current)
      dup = OwnerEndorsement.new(expense_record_id: "recExp1", budget_record_id: "recBud1",
                                 endorsed_by_person_id: "recPer2", endorsed_at: Time.current)
      assert_raises(ActiveRecord::RecordNotUnique) { dup.save!(validate: false) }
    end

    test "for_expense finds the endorsement by expense record id" do
      OwnerEndorsement.create!(expense_record_id: "recExp1", budget_record_id: "recBud1",
                               endorsed_by_person_id: "recPer1", endorsed_at: Time.current)
      assert OwnerEndorsement.for_expense("recExp1").exists?
      assert_not OwnerEndorsement.for_expense("recOther").exists?
    end
  end
end
