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

  test "on a public submission a new department name creates nothing and waits as a suggestion" do
    role = OpportunityRole.new(opportunity: opportunities(:internal_project_opportunity), position: "Puppeteer",
                               note: "Evenings only", department_name: "Puppetry", existing_department_only: true)

    assert_no_difference("Department.count") { 2.times { role.save! } }
    role.reload
    assert_nil role.department
    assert_equal "Puppetry", role.suggested_department
    assert_equal "Evenings only", role.note
  end

  test "on a public submission an existing department name still resolves" do
    role = OpportunityRole.new(position: "LX op", department_name: "lighting", existing_department_only: true)
    role.validate
    assert_equal departments(:lighting), role.department
  end

  test "on a public submission a full note still saves beside a typed department" do
    role = OpportunityRole.new(opportunity: opportunities(:internal_project_opportunity), position: "Puppeteer",
                               note: "x" * 250, department_name: "Puppetry", existing_department_only: true)
    assert role.valid?, role.errors.full_messages.to_sentence
  end

  test "on a public submission a typed department too long to keep is cut, not refused" do
    role = OpportunityRole.new(opportunity: opportunities(:internal_project_opportunity), position: "Puppeteer",
                               department_name: "P" * 300, existing_department_only: true)

    assert role.valid?, role.errors.full_messages.to_sentence
    assert_equal "P" * 255, role.suggested_department
  end

  test "setting a department clears the suggestion" do
    role = OpportunityRole.create!(opportunity: opportunities(:internal_project_opportunity), position: "Puppeteer",
                                   department_name: "Puppetry", existing_department_only: true)

    role.update!(department_name: "Lighting", existing_department_only: false)
    assert_equal departments(:lighting), role.reload.department
    assert_nil role.suggested_department
  end

  test "a role saved with no department keeps its suggestion" do
    role = OpportunityRole.create!(opportunity: opportunities(:internal_project_opportunity), position: "Puppeteer",
                                   department_name: "Puppetry", existing_department_only: true)

    role.update!(department_name: "", note: "Evenings only", existing_department_only: false)
    assert_nil role.reload.department
    assert_equal "Puppetry", role.suggested_department
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
