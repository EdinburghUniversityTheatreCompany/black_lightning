require "test_helper"

class OpportunityRoleTest < ActiveSupport::TestCase
  test "requires a position" do
    role = OpportunityRole.new(opportunity: opportunities(:internal_project_opportunity), position: nil)
    assert_not role.valid?
    assert role.errors[:position].present?
  end

  test "defaults to ordering" do
    roles = opportunities(:internal_project_opportunity).roles.to_a
    assert_equal [ "Stage Manager", "Set Manager", "Sound Technician" ], roles.map(&:position)
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

  test "on a public submission a new department name creates nothing and waits in the note" do
    role = OpportunityRole.new(opportunity: opportunities(:internal_project_opportunity), position: "Puppeteer",
                               note: "Evenings only", department_name: "Puppetry", existing_department_only: true)

    assert_no_difference("Department.count") { 2.times { role.save! } }
    assert_nil role.department
    assert_equal "Evenings only; Department: Puppetry", role.reload.note
  end

  test "on a public submission an existing department name still resolves" do
    role = OpportunityRole.new(position: "LX op", department_name: "lighting", existing_department_only: true)
    role.validate
    assert_equal departments(:lighting), role.department
  end

  test "on a public submission a note with no room for the typed department is refused, not cut" do
    role = OpportunityRole.new(opportunity: opportunities(:internal_project_opportunity), position: "Puppeteer",
                               note: "x" * 250, department_name: "Puppetry", existing_department_only: true)
    assert_not role.valid?
    assert role.errors[:note].present?
  end

  test "a saved role whose only edit is its department, set or cleared, is saved through the opportunity" do
    role = opportunity_roles(:internal_stage_manager)

    role.opportunity.update!(roles_attributes: { "0" => { id: role.id, position: role.position, department_name: "Sound" } })
    assert_equal departments(:sound), role.reload.department

    role.opportunity.update!(roles_attributes: { "0" => { id: role.id, position: role.position, department_name: "" } })
    assert_nil role.reload.department
  end

  test "blank department_name clears the department" do
    role = opportunity_roles(:internal_stage_manager)
    role.department_name = ""
    role.validate
    assert_nil role.department
  end
end
