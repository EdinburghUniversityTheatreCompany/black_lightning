require "test_helper"

module Reimbursements
  class NominalCodeSeedTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    test "a code is seeded once per cost centre with the count that justified it" do
      fringe = create_reimbursements_cost_centre(name: "Fringe 2", key: "fringe2", eusa_code: "F41")
      create_reimbursements_budget(name: "Marketing", nominal_code: "432320", cost_centre: fringe)
      create_reimbursements_budget(name: "Other", nominal_code: "432320", cost_centre: fringe)
      create_reimbursements_budget(name: "Set", nominal_code: "", cost_centre: fringe)

      plan = NominalCodeSeed.plan

      entry = plan.sole
      assert_equal "432320", entry[:code]
      assert_equal 2, entry[:budget_count]
      assert_equal fringe.id, entry[:cost_centre].id
    end

    test "apply! is idempotent and never duplicates an existing code" do
      fringe = create_reimbursements_cost_centre(name: "Fringe 2", key: "fringe2", eusa_code: "F41")
      create_reimbursements_budget(name: "Marketing", nominal_code: "432320", cost_centre: fringe)

      NominalCodeSeed.apply!
      NominalCodeSeed.apply!

      assert_equal 1, NominalCode.where(code: "432320", cost_centre: fringe).count
    end

    test "a second cost centre's matching code seeds as a separate row" do
      fringe = create_reimbursements_cost_centre(name: "Fringe 2", key: "fringe2", eusa_code: "F41")
      termtime = create_second_reimbursements_cost_centre
      create_reimbursements_budget(name: "Marketing", nominal_code: "432320", cost_centre: fringe)
      create_reimbursements_budget(name: "Marketing", nominal_code: "432320", cost_centre: termtime)

      NominalCodeSeed.apply!

      assert_equal 1, NominalCode.where(code: "432320", cost_centre: fringe).count
      assert_equal 1, NominalCode.where(code: "432320", cost_centre: termtime).count
    end

    test "a budget with no cost centre folds its code into the DEFAULT centre, and the plan states so" do
      default_centre = CostCentre.default
      other = create_second_reimbursements_cost_centre
      create_reimbursements_budget(name: "Venue Hire", nominal_code: "010000", cost_centre: nil)

      plan = NominalCodeSeed.plan

      entry = plan.find { |e| e[:code] == "010000" }
      assert_equal default_centre.id, entry[:cost_centre].id
      assert_equal 1, entry[:budget_count]
      assert_equal 1, entry[:unplaced_count],
        "the plan must state how many of the budgets behind this entry had no cost centre of their own"
      assert_not_equal other.id, entry[:cost_centre].id
    end

    test "the label is the most common budget name behind the code, not just the first" do
      cc = CostCentre.default
      create_reimbursements_budget(name: "Marketing", nominal_code: "432320", cost_centre: cc)
      create_reimbursements_budget(name: "Marketing", nominal_code: "432320", cost_centre: cc)
      create_reimbursements_budget(name: "Publicity", nominal_code: "432320", cost_centre: cc)

      entry = NominalCodeSeed.plan.sole
      assert_equal "Marketing", entry[:label]
    end

    test "apply! writes the plan's guessed label onto the created row" do
      cc = CostCentre.default
      create_reimbursements_budget(name: "Set Construction", nominal_code: "555000", cost_centre: cc)

      NominalCodeSeed.apply!

      code = NominalCode.find_by!(code: "555000", cost_centre: cc)
      assert_equal "Set Construction", code.label
    end

    test "a code already listed is left off the plan and untouched by apply!" do
      cc = CostCentre.default
      create_reimbursements_budget(name: "Marketing", nominal_code: "432320", cost_centre: cc)
      existing = create_reimbursements_nominal_code(code: "432320", cost_centre: cc, label: "Finance's own label")

      assert_empty NominalCodeSeed.plan

      NominalCodeSeed.apply!

      assert_equal "Finance's own label", existing.reload.label
    end

    test "a blank code across every budget produces no entries" do
      create_reimbursements_budget(name: "Nothing", nominal_code: "")

      assert_empty NominalCodeSeed.plan
    end

    # Two codes whose budgets share a name derive one label, and a centre's
    # labels are unique — so the seed has to qualify rather than abort, or the
    # committee's own data stops the whole list being seeded.
    test "two codes deriving one label are qualified rather than refused" do
      cc = CostCentre.default
      create_reimbursements_budget(name: "Marketing", nominal_code: "432320", cost_centre: cc)
      create_reimbursements_budget(name: "Marketing", nominal_code: "555555", cost_centre: cc)

      NominalCodeSeed.apply!

      labels = NominalCode.where(cost_centre: cc).order(:code).pluck(:code, :label)
      assert_equal [ [ "432320", "Marketing" ], [ "555555", "Marketing (555555)" ] ], labels
    end

    test "the plan says which labels it had to qualify" do
      cc = CostCentre.default
      create_reimbursements_budget(name: "Marketing", nominal_code: "432320", cost_centre: cc)
      create_reimbursements_budget(name: "Marketing", nominal_code: "555555", cost_centre: cc)

      qualified = NominalCodeSeed.plan.index_by { |entry| entry[:code] }

      assert_not qualified.fetch("432320")[:label_disambiguated]
      assert qualified.fetch("555555")[:label_disambiguated],
             "a label the seed had to change must not read as one the data stated"
    end

    # The rows #plan skips still hold their names, so a label finance already
    # owns is not free for a code seeded later.
    test "a label an already-listed code holds is not reused" do
      cc = CostCentre.default
      create_reimbursements_nominal_code(code: "432320", cost_centre: cc, label: "Marketing")
      create_reimbursements_budget(name: "Marketing", nominal_code: "555555", cost_centre: cc)

      NominalCodeSeed.apply!

      assert_equal "Marketing (555555)", NominalCode.find_by(cost_centre: cc, code: "555555").label
    end
  end
end
