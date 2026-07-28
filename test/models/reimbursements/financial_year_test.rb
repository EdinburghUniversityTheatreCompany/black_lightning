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

    # --- key (URL slug) ------------------------------------------------------

    test "key is derived from the label when blank" do
      year = FinancialYear.create!(label: "Fringe 2026")

      assert_equal "fringe-2026", year.key
      assert_equal "fringe-2026", year.to_param
    end

    test "an explicit key is kept" do
      year = FinancialYear.create!(label: "Fringe 2026", key: "f26")

      assert_equal "f26", year.key
    end

    test "keys are unique and URL-safe" do
      FinancialYear.create!(label: "Fringe 2026")

      dupe = FinancialYear.new(label: "Another 2026", key: "fringe-2026")
      assert_not dupe.valid?
      assert dupe.errors[:key].present?

      unsafe = FinancialYear.new(label: "Fringe 2028", key: "Fringe 2028!")
      assert_not unsafe.valid?
      assert unsafe.errors[:key].present?
    end

    # --- activate! -----------------------------------------------------------

    test "activate! moves the active flag off the incumbent year" do
      incumbent = FinancialYear.create!(label: "Fringe 2026", active: true)
      successor = FinancialYear.create!(label: "Fringe 2027")

      successor.activate!

      assert_predicate successor.reload, :active?
      assert_not_predicate incumbent.reload, :active?
      assert_equal successor, FinancialYear.current
    end

    test "activate! on the already-active year is a no-op" do
      year = FinancialYear.create!(label: "Fringe 2026", active: true)

      year.activate!

      assert_predicate year.reload, :active?
      assert_equal 1, FinancialYear.active.count
    end

    test "activate! leaves the incumbent active when the target cannot be saved" do
      incumbent = FinancialYear.create!(label: "Fringe 2026", active: true)
      successor = FinancialYear.create!(label: "Fringe 2027")
      # A year that has become invalid since it was created (label blanked by
      # another session) must not take the active flag off the live year on its
      # way to failing — that would leave the portal with NO active year at all.
      successor.update_column(:label, "")

      assert_raises(ActiveRecord::RecordInvalid) { successor.activate! }

      assert_predicate incumbent.reload, :active?
      assert_equal incumbent, FinancialYear.current
    end

    # --- ordering ------------------------------------------------------------

    test "recent_first puts the newest year at the top" do
      old = FinancialYear.create!(label: "Fringe 2025", starts_on: Date.new(2025, 8, 1))
      new = FinancialYear.create!(label: "Fringe 2026", starts_on: Date.new(2026, 8, 1))
      undated = FinancialYear.create!(label: "Fringe 2099")

      # A year with no start date yet sorts to the top: it is the one being set
      # up, so it is the one the operator is looking for.
      assert_equal [ undated, new, old ], FinancialYear.recent_first.to_a
    end
  end
end
