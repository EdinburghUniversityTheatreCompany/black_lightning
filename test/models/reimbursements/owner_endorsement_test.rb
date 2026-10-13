require "test_helper"

module Reimbursements
  class OwnerEndorsementTest < ActiveSupport::TestCase
    test "an endorsement is an owner's or a finance override, never neither or both" do
      base = { expense_record_id: "recExp1", budget_record_id: "recBud1", endorsed_at: Time.current }
      owner = { endorsed_by_person_id: "recPer1" }
      override = { overridden_by: users(:admin), note: "no owner has an account" }

      [ [ owner, :owner_endorsement?, :finance_override? ],
        [ override, :finance_override?, :owner_endorsement? ] ].each do |attrs, kind, other|
        endorsement = OwnerEndorsement.new(**base, **attrs)
        assert endorsement.valid?, kind
        assert endorsement.public_send(kind), kind
        assert_not endorsement.public_send(other), kind
      end
      [ {}, owner.merge(override) ].each do |attrs|
        endorsement = OwnerEndorsement.new(**base, **attrs)
        assert_not endorsement.valid?, attrs.keys.inspect
        assert endorsement.errors[:base].present?, attrs.keys.inspect
      end
    end

    test "only one endorsement can exist per expense (any one owner suffices)" do
      OwnerEndorsement.create!(expense_record_id: "recExp1", budget_record_id: "recBud1",
                               endorsed_by_person_id: "recPer1", endorsed_at: Time.current)
      dup = OwnerEndorsement.new(expense_record_id: "recExp1", budget_record_id: "recBud1",
                                 endorsed_by_person_id: "recPer2", endorsed_at: Time.current)
      assert_raises(ActiveRecord::RecordNotUnique) { dup.save!(validate: false) }
    end
  end
end
