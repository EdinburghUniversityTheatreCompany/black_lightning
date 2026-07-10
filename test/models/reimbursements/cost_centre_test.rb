require "test_helper"

module Reimbursements
  class CostCentreTest < ActiveSupport::TestCase
    test "fringe is the default cost centre with the EUSA F40 code" do
      assert_equal "fringe", CostCentre.default.key
      assert_equal "F40", CostCentre.default.eusa_code
    end

    test "carries distinct receive and send mailboxes" do
      fringe = CostCentre.default
      assert_equal "reimbursements@bedlamfringe.co.uk", fringe.receive_mailbox
      assert_equal "reimbursements@bedlamfringe.co.uk", fringe.send_mailbox
    end

    test "requires key, name, eusa_code and both mailboxes" do
      cost_centre = CostCentre.new
      assert_not cost_centre.valid?
      assert_includes cost_centre.errors.attribute_names, :key
      assert_includes cost_centre.errors.attribute_names, :name
      assert_includes cost_centre.errors.attribute_names, :eusa_code
      assert_includes cost_centre.errors.attribute_names, :receive_mailbox
      assert_includes cost_centre.errors.attribute_names, :send_mailbox
    end

    test "key is unique" do
      duplicate = CostCentre.new(key: "fringe", name: "Dup", eusa_code: "F40",
        receive_mailbox: "a@b.co", send_mailbox: "a@b.co")
      assert_not duplicate.valid?
      assert_includes duplicate.errors.attribute_names, :key
    end
  end
end
