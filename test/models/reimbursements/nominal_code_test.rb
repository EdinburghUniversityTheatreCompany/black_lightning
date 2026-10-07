require "test_helper"

module Reimbursements
  class NominalCodeTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    test "a code is unique within its cost centre but not across centres" do
      fringe = CostCentre.default
      termtime = create_second_reimbursements_cost_centre

      create_reimbursements_nominal_code(code: "432320", cost_centre: fringe)
      dupe = NominalCode.new(code: "432320", cost_centre: fringe, label: "Marketing")
      assert_not dupe.valid?
      assert dupe.errors[:code].present?

      other = NominalCode.new(code: "432320", cost_centre: termtime, label: "Marketing")
      assert other.valid?, "the same code in another centre is a different account"
    end

    # The trailing space is PAD SPACE: 'abc' = 'abc ' under utf8mb4_unicode_ci but
    # not the server default utf8mb4_0900_ai_ci, so it guards the pinned collation.
    test "a duplicate code is rejected under the column's collation" do
      [ [ "abc123", "ABC123" ], [ "cafe1", "café1" ], [ "432320", "432320 " ] ].each do |code, variant|
        create_reimbursements_nominal_code(code: code)
        dupe = NominalCode.new(code: variant, cost_centre: CostCentre.default, label: "Marketing #{variant}")

        assert_not dupe.valid?, "#{variant.inspect} should duplicate #{code.inspect}"
        assert dupe.errors[:code].present?
      end
    end

    test "a label is unique within its cost centre, case-insensitively" do
      cc = CostCentre.default
      create_reimbursements_nominal_code(code: "432320", cost_centre: cc, label: "Marketing")
      dupe = NominalCode.new(code: "431000", cost_centre: cc, label: "marketing")

      assert_not dupe.valid?
      assert dupe.errors[:label].present?
    end

    test "another centre may reuse a label, as it may reuse a code" do
      home = CostCentre.default
      other = create_second_reimbursements_cost_centre
      create_reimbursements_nominal_code(code: "432320", cost_centre: home, label: "Marketing")

      assert NominalCode.new(code: "500000", cost_centre: other, label: "Marketing").valid?
    end

    test "for_cost_centre scopes to the centre and orders by code" do
      fringe = CostCentre.default
      termtime = create_second_reimbursements_cost_centre

      create_reimbursements_nominal_code(code: "432320", cost_centre: fringe)
      create_reimbursements_nominal_code(code: "041000", cost_centre: fringe)
      create_reimbursements_nominal_code(code: "010000", cost_centre: termtime)

      assert_equal %w[041000 432320], NominalCode.for_cost_centre(fringe).map(&:code)
    end
  end
end
