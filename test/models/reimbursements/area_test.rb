require "test_helper"

module Reimbursements
  class AreaTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    test "requires a name" do
      area = Area.new(name: "")
      assert_not area.valid?
      assert area.errors[:name].present?
    end

    test "a budget belongs to an area, and an area-less budget is still valid" do
      area = create_reimbursements_area(name: "Cogito")
      in_area = create_reimbursements_budget(name: "Cogito: Marketing", area: area)
      loose = create_reimbursements_budget(name: "Contingency")

      assert_equal area, in_area.area
      assert_nil loose.area
      assert_equal [ in_area ], area.budgets.to_a
    end

    test "record_id is the id as a string, like a budget's" do
      area = create_reimbursements_area(name: "Cogito")
      assert_equal area.id.to_s, area.record_id
    end
  end
end
