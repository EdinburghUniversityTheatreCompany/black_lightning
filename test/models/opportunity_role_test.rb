require "test_helper"

class OpportunityRoleTest < ActiveSupport::TestCase
  test "requires a position" do
    role = OpportunityRole.new(opportunity: opportunities(:internal_project_opportunity), position: nil)
    assert_not role.valid?
    assert role.errors[:position].present?
  end

  test "belongs to an opportunity" do
    assert_equal opportunities(:internal_project_opportunity), opportunity_roles(:internal_stage_manager).opportunity
  end

  test "belongs to a department" do
    assert_equal departments(:stage_management), opportunity_roles(:internal_stage_manager).department
  end

  test "defaults to ordering" do
    roles = opportunities(:internal_project_opportunity).roles.to_a
    assert_equal [ "Stage Manager", "Set Manager", "Sound Technician" ], roles.map(&:position)
  end

  test "stores an optional note" do
    assert_equal "Build weekends only", opportunity_roles(:internal_set_manager).note
  end

  test "department_name falls back to the associated department" do
    assert_equal "Stage Management", opportunity_roles(:internal_stage_manager).department_name
  end

  test "department_name resolves to an existing department (case-insensitive)" do
    role = OpportunityRole.new(position: "ASM", department_name: "stage management")
    role.validate
    assert_equal departments(:stage_management), role.department
  end

  test "department_name creates a new department when it does not match" do
    role = OpportunityRole.new(opportunity: opportunities(:internal_project_opportunity),
                               position: "Rigger", department_name: "Rigging")
    assert_difference("Department.count", 1) { role.save! }
    assert_equal "Rigging", role.department.name
  end

  test "blank department_name clears the department" do
    role = opportunity_roles(:internal_stage_manager)
    role.department_name = ""
    role.validate
    assert_nil role.department
  end
end
