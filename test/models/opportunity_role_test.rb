require "test_helper"

class OpportunityRoleTest < ActiveSupport::TestCase
  test "requires a position" do
    role = OpportunityRole.new(opportunity: opportunities(:internal_project_opportunity), position: nil, category: :stage)
    assert_not role.valid?
    assert role.errors[:position].present?
  end

  test "belongs to an opportunity" do
    assert_equal opportunities(:internal_project_opportunity), opportunity_roles(:internal_stage_manager).opportunity
  end

  test "category enum maps to readable values" do
    assert_equal 2, OpportunityRole.categories[:stage]
    assert opportunity_roles(:internal_stage_manager).stage?
  end

  test "defaults to ordering" do
    roles = opportunities(:internal_project_opportunity).roles.to_a
    assert_equal [ "Stage Manager", "Set Manager", "Sound Technician" ], roles.map(&:position)
  end

  test "stores an optional note" do
    assert_equal "Build weekends only", opportunity_roles(:internal_set_manager).note
  end

  test "category_label humanises most categories and special-cases FOH" do
    assert_equal "Stage", OpportunityRole.new(category: :stage).category_label
    assert_equal "FOH", OpportunityRole.new(category: :foh).category_label
  end
end
