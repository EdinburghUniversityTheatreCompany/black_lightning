require "test_helper"

module Reimbursements
  class CostCentreTest < ActiveSupport::TestCase
    test "fringe is the default cost centre with the EUSA F40 code" do
      assert_equal CostCentre::FRINGE, CostCentre.default
      assert_equal "F40", CostCentre.default.eusa_code
      assert_equal "reimbursements@bedlamfringe.co.uk", CostCentre.default.mailbox
      assert_includes CostCentre.all, CostCentre::FRINGE
    end

    test "cost centres are frozen value objects" do
      assert CostCentre::FRINGE.frozen?
    end
  end
end
