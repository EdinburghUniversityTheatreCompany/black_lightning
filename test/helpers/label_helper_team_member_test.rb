require "test_helper"

class LabelHelperTeamMemberTest < ActionView::TestCase
  include LabelHelper

  setup do
    @team_member = FactoryBot.create(:team_member)
  end

  test "DM trained user should have the DM trained label" do
    assert_not @team_member.user.has_role?("DM Trained")
    assert_labels_not_includes @team_member, "DM Trained"

    @team_member.user.add_role("DM Trained")
    assert_labels_includes @team_member, "DM Trained"
  end

  test "Bar trained user should have the Bar trained label" do
    assert_not @team_member.user.has_role?("Bar Trained")
    assert_labels_not_includes @team_member, "Bar Trained"

    @team_member.user.add_role("Bar Trained")
    assert_labels_includes @team_member, "Bar Trained"
  end

  test "Tool trained user should have the Tool trained label" do
    assert_not @team_member.user.has_role?("Tool Trained")
    assert_labels_not_includes @team_member, "Tool Trained"

    @team_member.user.add_role("Tool Trained")
    assert_labels_includes @team_member, "Tool Trained"
  end

  test "First Aid Trained user should have the First Aid Trained label" do
    assert_not @team_member.user.has_role?("First Aid Trained")
    assert_labels_not_includes @team_member, "First Aid Trained"

    @team_member.user.add_role("First Aid Trained")
    assert_labels_includes @team_member, "First Aid Trained"
  end

  test "Members should not show a membership label" do
    @team_member.teamwork.update(start_date: Date.current, end_date: Date.current + 1.days)

    assert_labels_not_includes @team_member, "Life Member"
    assert_labels_not_includes @team_member, "Member"
  end

  test "Life Members should not show a membership label" do
    @team_member.teamwork.update(start_date: Date.current, end_date: Date.current + 1.days)

    @team_member.user.remove_role("Member")
    @team_member.user.add_role("Life Member")

    assert_labels_not_includes @team_member, "Life Member"
    assert_labels_not_includes @team_member, "Member"
  end

  test "Show in this academic year should warn for non-member" do
    @team_member.teamwork.update(start_date: Date.current, end_date: Date.current + 1.days)

    @team_member.user.remove_role("Member")
    assert_labels_includes @team_member, "Non-Member"
  end

  test "shows in previous academic years should not warn for non-members" do
    @team_member.teamwork.update(start_date: 1.year.ago - 5.days, end_date: 1.year.ago - 4.days)

    @team_member.user.remove_role("Member")
    assert_labels_not_includes @team_member, "Non-Member"
  end

  test "Show in this academic year should warn for non-member life members" do
    @team_member.teamwork.update(start_date: Date.current, end_date: Date.current + 1.days)

    @team_member.user.remove_role("Member")
    @team_member.user.add_role("Life Member")

    assert_labels_includes @team_member, "Non-EUTC Member"
  end

  test "shows in previous academic years should not warn for non-members life members" do
    @team_member.teamwork.update(start_date: 1.year.ago - 5.days, end_date: 1.year.ago - 4.days)

    @team_member.user.remove_role("Member")
    assert_labels_not_includes @team_member, "Non-EUTC Member"
  end

  test "user in staffing debt on deadline" do
    FactoryBot.create(:overdue_staffing_debt, user: @team_member.user)

    deadline = 1.week.from_now.to_date

    label = team_member_labels_for(@team_member, deadline).first

    assert_includes label[:text], "In staffing debt now"
    assert_equal "bg-danger", label[:label_class]
  end

  test "user in maintenance debt on deadline" do
    FactoryBot.create(:overdue_maintenance_debt, user: @team_member.user)

    deadline = 1.week.from_now.to_date

    label = team_member_labels_for(@team_member, deadline).first

    assert_includes label[:text], "In maintenance debt now"
    assert_equal "bg-danger", label[:label_class]
  end

  test "user is in staffing debt and not in maintenace debt now but is on the editing deadline" do
    FactoryBot.create(:overdue_staffing_debt, user: @team_member.user)
    FactoryBot.create(:maintenance_debt, user: @team_member.user, due_by: 5.days.from_now)

    deadline = 1.week.from_now.to_date

    labels = team_member_labels_for(@team_member, deadline)

    assert_equal 2, labels.count

    assert_includes labels.first[:text], "In staffing debt now"
    assert_equal "bg-danger", labels.first[:label_class]

    assert_includes labels.last[:text], "In maintenance debt on the editing deadline"
    assert_equal "bg-danger", labels.last[:label_class]
  end

  test "User profiles for non-members should show membership labels" do
    @team_member.user.remove_role("Member")
    labels = user_profile_labels_for(@team_member.user).map { |l| l[:text] }

    assert_not_includes labels, "Member"
    assert_not_includes labels, "EUTC Member"
    assert_not_includes labels, "Life Member"
    assert_not_includes labels, "Non-EUTC Member"
    assert_includes labels, "Non-Member"
  end

  test "User profiles for members should show membership labels" do
    labels = user_profile_labels_for(@team_member.user).map { |l| l[:text] }

    assert_includes labels, "Member"
    assert_not_includes labels, "EUTC Member"
    assert_not_includes labels, "Life Member"
    assert_not_includes labels, "Non-EUTC Member"
    assert_not_includes labels, "Non-Member"
  end

  test "User profiles for non-member/life members should show membership labels" do
    @team_member.user.remove_role("Member")
    @team_member.user.add_role("Life Member")

    labels = user_profile_labels_for(@team_member.user).map { |l| l[:text] }

    assert_not_includes labels, "Member"
    assert_not_includes labels, "EUTC Member"
    assert_includes labels, "Life Member"
    assert_includes labels, "Non-EUTC Member"
    assert_not_includes labels, "Non-Member"
  end

  test "User profiles for member/life members should show membership labels" do
    @team_member.user.add_role("Life Member")

    labels = user_profile_labels_for(@team_member.user).map { |l| l[:text] }

    assert_not_includes labels, "Member"
    assert_includes labels, "EUTC Member"
    assert_includes labels, "Life Member"
    assert_not_includes labels, "Non-EUTC Member"
    assert_not_includes labels, "Non-Member"
  end


  test "User profiles for members should show staffing debts" do
    FactoryBot.create(:overdue_staffing_debt, user: @team_member.user)

    assert_labels_includes @team_member, "In staffing debt now"
  end

  test "User profiles for members should show maintenance debts" do
    FactoryBot.create(:overdue_maintenance_debt, user: @team_member.user)

    assert_labels_includes @team_member, "In maintenance debt now"
  end

  test "User profiles for members should show staffing & maintenance debts" do
    FactoryBot.create(:overdue_maintenance_debt, user: @team_member.user)
    FactoryBot.create(:overdue_staffing_debt, user: @team_member.user)

    assert_labels_includes @team_member, "In staffing and maintenance debt now"
  end

  private

  def assert_labels_includes(team_member, value_to_match, date = Date.current)
    labels =  team_member_labels_for(@team_member, date).map { |l| ActionView::Base.full_sanitizer.sanitize(l[:text]) }

    assert_includes labels, value_to_match
  end

  def assert_labels_not_includes(team_member, value_to_match, date = Date.current)
    labels =  team_member_labels_for(@team_member, date).map { |l| ActionView::Base.full_sanitizer.sanitize(l[:text]) }

    assert_not_includes labels, value_to_match
  end
end
