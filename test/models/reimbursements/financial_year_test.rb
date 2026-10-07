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

    test "key is derived from the label unless given" do
      year = FinancialYear.create!(label: "Fringe 2026")

      assert_equal "fringe-2026", year.key
      assert_equal "fringe-2026", year.to_param
      assert_equal "f27", FinancialYear.create!(label: "Fringe 2027", key: "f27").key
    end

    test "a key must be URL-safe" do
      unsafe = FinancialYear.new(label: "Fringe 2028", key: "Fringe 2028!")
      assert_not unsafe.valid?
      assert unsafe.errors[:key].present?
    end

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
      # A year invalid since creation (label blanked elsewhere) must not take the flag off the
      # live year on its way to failing, or the portal has no active year.
      successor.update_column(:label, "")

      assert_raises(ActiveRecord::RecordInvalid) { successor.activate! }

      assert_predicate incumbent.reload, :active?
      assert_equal incumbent, FinancialYear.current
    end

    test "a year that is not active is past once it has started, draft before" do
      active = FinancialYear.create!(label: "Fringe 2027", active: true)
      # Last year is still being paid out, so it must not read as a draft.
      past = FinancialYear.create!(label: "Fringe 2026", starts_on: 1.year.ago.to_date)
      upcoming = FinancialYear.create!(label: "Fringe 2028", starts_on: 1.year.from_now.to_date)
      undated = FinancialYear.create!(label: "Fringe 2099")

      assert_equal :active, active.status
      assert_equal :past, past.status
      assert_equal :draft, upcoming.status
      assert_equal :draft, undated.status
    end

    test "recent_first puts the newest year at the top" do
      old = FinancialYear.create!(label: "Fringe 2025", starts_on: Date.new(2025, 8, 1))
      new = FinancialYear.create!(label: "Fringe 2026", starts_on: Date.new(2026, 8, 1))
      undated = FinancialYear.create!(label: "Fringe 2099")

      # A year with no start date sorts first: it is the one being set up.
      assert_equal [ undated, new, old ], FinancialYear.recent_first.to_a
    end
  end
end
