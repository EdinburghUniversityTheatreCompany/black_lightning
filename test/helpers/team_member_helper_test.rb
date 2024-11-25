require 'test_helper'

class TeamMemberHelperTest < ActionView::TestCase
  setup do
    @team_member = FactoryBot.create(:team_member)
  end

  test 'DM trained user should have the DM trained label' do
    assert_not @team_member.user.has_role?("DM Trained")
    assert_not_includes team_member_labels_for(@team_member, Date.current).join(';'), 'DM Trained'

    @team_member.user.add_role("DM Trained")
    assert_includes team_member_labels_for(@team_member, Date.current).join(';'), 'DM Trained'
  end

  test 'Bar trained user should have the Bar trained label' do
    assert_not @team_member.user.has_role?("Bar Trained")
    assert_not_includes team_member_labels_for(@team_member, Date.current).join(';'), 'Bar Trained'

    @team_member.user.add_role("Bar Trained")
    assert_includes team_member_labels_for(@team_member, Date.current).join(';'), 'Bar Trained'
  end

  test 'First Aid Trained user should have the First Aid Trained label' do
    assert_not @team_member.user.has_role?("First Aid Trained")
    assert_not_includes team_member_labels_for(@team_member, Date.current).join(';'), 'First Aid Trained'

    @team_member.user.add_role("First Aid Trained")
    assert_includes team_member_labels_for(@team_member, Date.current).join(';'), 'First Aid Trained'
  end

  test 'Show in this academic year should warn for non-member' do
    @team_member.teamwork.update(start_date: Date.current, end_date: Date.current + 1.days)

    @team_member.user.remove_role("Member")
    labels = team_member_labels_for(@team_member, nil).map { |l| l[:text] }
    assert_includes labels, 'Not A Member'
  end
  
  test 'shows in previous academic years should not warn for non-members' do
    @team_member.teamwork.update(start_date: 1.year.ago - 5.days, end_date: 1.year.ago - 4.days)

    @team_member.user.remove_role("Member")
    labels = team_member_labels_for(@team_member, nil).map { |l| l[:text] }
    assert_not_includes labels, 'Not A Member'
  end
  
  test 'user in staffing debt on deadline' do
    FactoryBot.create(:overdue_staffing_debt, user: @team_member.user)

    deadline = 1.week.from_now.to_date

    label = team_member_labels_for(@team_member, deadline).first

    assert_includes label[:text], "In staffing Debt"
    assert_equal :danger, label[:label_class]
  end
  
  test 'user in maintenance debt on deadline' do
    FactoryBot.create(:overdue_maintenance_debt, user: @team_member.user)

    deadline = 1.week.from_now.to_date

    label = team_member_labels_for(@team_member, deadline).first

    assert_includes label[:text], "In maintenance Debt"
    assert_equal :danger, label[:label_class]
  end

  test 'user is in staffing debt and not in maintenace debt now but is on the editing deadline' do
    FactoryBot.create(:overdue_staffing_debt, user: @team_member.user)
    FactoryBot.create(:maintenance_debt, user: @team_member.user, due_by: 5.days.from_now)

    deadline = 1.week.from_now.to_date

    labels = team_member_labels_for(@team_member, deadline)

    assert_equal 2, labels.count

    assert_includes labels.first[:text], "In staffing Debt"
    assert_equal :danger, labels.first[:label_class]

    assert_includes labels.last[:text], "In staffing and maintenance Debt on the editing deadline"
    assert_equal :danger, labels.last[:label_class]
  end
end
