require "test_helper"

module Reimbursements
  class NominalCodeTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    test "a code is unique within its cost centre but not across centres" do
      fringe = create_reimbursements_cost_centre(name: "Fringe", key: "fringe2", eusa_code: "F41")
      termtime = create_second_reimbursements_cost_centre

      create_reimbursements_nominal_code(code: "432320", cost_centre: fringe)
      dupe = NominalCode.new(code: "432320", cost_centre: fringe, label: "Marketing")
      assert_not dupe.valid?
      assert dupe.errors[:code].present?

      other = NominalCode.new(code: "432320", cost_centre: termtime, label: "Marketing")
      assert other.valid?, "the same code in another centre is a different account"
    end

    test "a duplicate code is rejected case-insensitively" do
      cc = Reimbursements::CostCentre.default
      create_reimbursements_nominal_code(code: "abc123", cost_centre: cc)
      dupe = NominalCode.new(code: "ABC123", cost_centre: cc, label: "Marketing")
      assert_not dupe.valid?
      assert dupe.errors[:code].present?
    end

    test "a duplicate code is rejected accent-insensitively" do
      cc = Reimbursements::CostCentre.default
      create_reimbursements_nominal_code(code: "cafe1", cost_centre: cc)
      dupe = NominalCode.new(code: "café1", cost_centre: cc, label: "Marketing")
      assert_not dupe.valid?
      assert dupe.errors[:code].present?
    end

    # PAD SPACE: 'abc' = 'abc ' under utf8mb4_unicode_ci but not under
    # utf8mb4_0900_ai_ci (the MySQL 8 server default) — a regression guard for
    # the table actually carrying the collation the migration pins.
    test "a trailing-space code is rejected as a duplicate" do
      cc = Reimbursements::CostCentre.default
      create_reimbursements_nominal_code(code: "432320", cost_centre: cc)
      dupe = NominalCode.new(code: "432320 ", cost_centre: cc, label: "Marketing")
      assert_not dupe.valid?
      assert dupe.errors[:code].present?
    end

    test "active defaults to true, and false persists" do
      code = NominalCode.create!(code: "999999", label: "Test",
                                 cost_centre: Reimbursements::CostCentre.default)
      assert code.active?

      code.update!(active: false)
      assert_not code.reload.active?
    end

    test "the helper derives a distinct default label per code" do
      a = create_reimbursements_nominal_code(code: "111111")
      b = create_reimbursements_nominal_code(code: "222222")
      assert_not_equal a.label, b.label
    end

    test "a zero-padded code keeps its padding" do
      code = create_reimbursements_nominal_code(code: "041000")
      assert_equal "041000", code.reload.code
    end

    test "code and label must both be present" do
      # create_reimbursements_cost_centre requires key:/name:/eusa_code: with no
      # defaults, so the brief's bare call would raise ArgumentError — the
      # fixture cost centre (loaded for every test) stands in instead.
      blank = NominalCode.new(cost_centre: Reimbursements::CostCentre.default)
      assert_not blank.valid?
      assert blank.errors[:code].present?
      assert blank.errors[:label].present?
    end

    test "for_cost_centre scopes to the centre and orders by code" do
      fringe = create_reimbursements_cost_centre(name: "Fringe", key: "fringe3", eusa_code: "F42")
      termtime = create_second_reimbursements_cost_centre

      create_reimbursements_nominal_code(code: "432320", cost_centre: fringe)
      create_reimbursements_nominal_code(code: "041000", cost_centre: fringe)
      create_reimbursements_nominal_code(code: "010000", cost_centre: termtime)

      assert_equal %w[041000 432320], NominalCode.for_cost_centre(fringe).map(&:code)
    end
  end
end
