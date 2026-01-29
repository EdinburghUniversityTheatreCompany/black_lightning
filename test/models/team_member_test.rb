require "test_helper"

class TeamMemberTest < ActiveSupport::TestCase
  include AcademicYearHelper

  test "should validate uniqueness in parent collection with nested attributes scenario" do
    event = FactoryBot.create(:event)
    user = FactoryBot.create(:user)

    # Build BOTH team members in memory (simulates nested attributes)
    # This is what happens when form submits same user twice with different positions
    tm1 = event.team_members.build(user_id: user.id, position: "Director")
    tm2 = event.team_members.build(user_id: user.id, position: "Producer")

    # The first one should be valid
    assert tm1.valid?, "First team member should be valid"

    # The second one should be invalid (duplicate user in collection)
    assert_not tm2.valid?, "Second team member should not be valid when user is already in collection"
    assert tm2.errors[:user_id].any? { |msg| msg.match?(/already a team member/) }, "Should have error message about duplicate"
  end

  test "should allow same user on different events" do
    event1 = FactoryBot.create(:event)
    event2 = FactoryBot.create(:event)
    user = FactoryBot.create(:user)

    # Create team member on first event
    event1.team_members.create!(user_id: user.id, position: "Director")

    # Should allow same user on different event
    team_member2 = event2.team_members.build(user_id: user.id, position: "Producer")

    assert team_member2.valid?, "Should be valid when user is on different event"
  end

  test "should allow different users on same event" do
    event = FactoryBot.create(:event)
    user1 = FactoryBot.create(:user)
    user2 = FactoryBot.create(:user)

    # Create first team member
    event.team_members.create!(user_id: user1.id, position: "Director")

    # Should allow different user
    team_member2 = event.team_members.build(user_id: user2.id, position: "Producer")

    assert team_member2.valid?, "Should be valid when different user"
  end

  test "should work with Proposal which does not have STI type column" do
    proposal = FactoryBot.create(:proposal)
    user = FactoryBot.create(:user)

    # Build a team member on a Proposal (non-STI model)
    # This should not raise NoMethodError for type_changed?
    team_member = proposal.team_members.build(user_id: user.id, position: "Director")

    # Should be able to validate without error
    assert_nothing_raised { team_member.valid? }
  end

  test "should auto-create debts when added to show with debt configuration" do
    show = FactoryBot.create(:show,
      start_date: start_of_year,
      end_date: start_of_year.advance(days: 5),
      team_member_count: 0,
      maintenance_debt_amount: 1,
      maintenance_debt_start: Date.current.advance(days: 14),
      staffing_debt_amount: 2,
      staffing_debt_start: Date.current.advance(days: 14)
    )
    user = FactoryBot.create(:user)

    assert_difference "Admin::MaintenanceDebt.count", 1 do
      assert_difference "Admin::StaffingDebt.count", 2 do
        show.team_members.create!(user_id: user.id, position: "Director")
      end
    end

    assert_equal 1, user.admin_maintenance_debts.where(show: show).count
    assert_equal 2, user.admin_staffing_debts.where(show: show).count
  end

  test "should not create debts when added to show without debt configuration" do
    show = FactoryBot.create(:show, team_member_count: 0)
    user = FactoryBot.create(:user)

    assert_no_difference "Admin::MaintenanceDebt.count" do
      assert_no_difference "Admin::StaffingDebt.count" do
        show.team_members.create!(user_id: user.id, position: "Director")
      end
    end
  end

  test "should not create debts when added to non-show teamwork" do
    event = FactoryBot.create(:event)
    user = FactoryBot.create(:user)

    assert_no_difference "Admin::MaintenanceDebt.count" do
      assert_no_difference "Admin::StaffingDebt.count" do
        event.team_members.create!(user_id: user.id, position: "Director")
      end
    end
  end
end
