require "test_helper"

module Reimbursements
  class FinancialYearTest < ActiveSupport::TestCase
    test "only one financial year may be active" do
      FinancialYear.create!(label: "Fringe 2026", active: true)
      second = FinancialYear.new(label: "Fringe 2027", active: true)

      assert_not second.valid?
      assert second.errors[:active].present?

      second.active = false
      assert second.valid?
    end

    test "current returns the active year" do
      year = FinancialYear.create!(label: "Fringe 2026", active: true)
      FinancialYear.create!(label: "Fringe 2025")
      assert_equal year, FinancialYear.current
    end

    test "labels are unique" do
      FinancialYear.create!(label: "Fringe 2026")
      dupe = FinancialYear.new(label: "Fringe 2026")
      assert_not dupe.valid?
    end
  end
end
