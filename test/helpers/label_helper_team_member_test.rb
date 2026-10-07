require "test_helper"

class LabelHelperTeamMemberTest < ActionView::TestCase
  include LabelHelper

  setup do
    @team_member = FactoryBot.create(:team_member)
  end

  test "a trained role shows as a label" do
    [ "DM Trained", "Bar Trained", "Tool Trained", "First Aid Trained" ].each do |role|
      assert_not_includes label_texts, role
      @team_member.user.add_role(role)
      assert_includes label_texts, role
    end
  end

  test "Members should not show a membership label" do
    @team_member.teamwork.update(start_date: Date.current, end_date: Date.current + 1.days)

    assert_not_includes label_texts, "Life Member"
    assert_not_includes label_texts, "Member"
  end

  test "Life Members should not show a membership label" do
    @team_member.teamwork.update(start_date: Date.current, end_date: Date.current + 1.days)

    @team_member.user.remove_role("Member")
    @team_member.user.add_role("Life Member")

    assert_not_includes label_texts, "Life Member"
    assert_not_includes label_texts, "Member"
  end

  test "Show in this academic year should warn for non-member" do
    @team_member.teamwork.update(start_date: Date.current, end_date: Date.current + 1.days)

    @team_member.user.remove_role("Member")
    assert_includes label_texts, "Non-Member"
  end

  test "shows in previous academic years should not warn for non-members" do
    @team_member.teamwork.update(start_date: 1.year.ago - 5.days, end_date: 1.year.ago - 4.days)

    @team_member.user.remove_role("Member")
    assert_not_includes label_texts, "Non-Member"
  end

  test "Show in this academic year should warn for non-member life members" do
    @team_member.teamwork.update(start_date: Date.current, end_date: Date.current + 1.days)

    @team_member.user.remove_role("Member")
    @team_member.user.add_role("Life Member")

    assert_includes label_texts, "Non-EUTC Member"
  end

  test "shows in previous academic years should not warn for non-members life members" do
    @team_member.teamwork.update(start_date: 1.year.ago - 5.days, end_date: 1.year.ago - 4.days)

    @team_member.user.remove_role("Member")
    assert_not_includes label_texts, "Non-EUTC Member"
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

  test "user profiles state membership" do
    user = @team_member.user
    assert_equal [ "Member" ], profile_texts(user)

    user.add_role("Life Member")
    assert_equal [ "Life Member", "EUTC Member" ], profile_texts(user)

    user.remove_role("Member")
    assert_equal [ "Life Member", "Non-EUTC Member" ], profile_texts(user)

    user.remove_role("Life Member")
    assert_equal [ "Non-Member" ], profile_texts(user)
  end

  test "a user in both debts gets one combined label" do
    FactoryBot.create(:overdue_maintenance_debt, user: @team_member.user)
    FactoryBot.create(:overdue_staffing_debt, user: @team_member.user)

    assert_includes label_texts, "In staffing and maintenance debt now"
  end

  private

  def label_texts
    team_member_labels_for(@team_member, Date.current).map { |l| ActionView::Base.full_sanitizer.sanitize(l[:text]) }
  end

  def profile_texts(user) = user_profile_labels_for(user).pluck(:text)
end
