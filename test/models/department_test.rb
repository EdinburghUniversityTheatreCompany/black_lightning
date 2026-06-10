require "test_helper"

class DepartmentTest < ActiveSupport::TestCase
  test "requires a name" do
    department = Department.new(name: nil)
    assert_not department.valid?
    assert department.errors[:name].present?
  end

  test "name is unique case-insensitively" do
    duplicate = Department.new(name: "lighting")
    assert_not duplicate.valid?
    assert duplicate.errors[:name].present?
  end

  test "match_term_list splits on commas and newlines and lowercases" do
    department = Department.new(match_terms: "Stage Manager, ASM\nDeputy Stage ")
    assert_equal [ "stage manager", "asm", "deputy stage" ], department.match_term_list
  end

  test "match_for returns the first department whose term is in the position" do
    assert_equal departments(:stage_management), Department.match_for("Assistant Stage Manager")
    assert_equal departments(:lighting), Department.match_for("Lighting Designer")
  end

  test "match_for returns nil when nothing matches" do
    assert_nil Department.match_for("Dramaturg")
    assert_nil Department.match_for("")
  end

  test "find_or_build_by_name finds case-insensitively or builds a new record" do
    assert_equal departments(:sound), Department.find_or_build_by_name("SOUND")

    built = Department.find_or_build_by_name("Rigging")
    assert built.new_record?
    assert_equal "Rigging", built.name
  end

  test "suggestions exposes names and terms for the Stimulus controller" do
    suggestion = Department.suggestions.find { |s| s[:name] == "Stage Management" }
    assert_includes suggestion[:terms], "asm"
  end
end
