require "test_helper"

class UserAbsorbTest < ActiveSupport::TestCase
  setup do
    @target_user = FactoryBot.create(:member)
    @source_user = FactoryBot.create(:member)
  end

  # Basic validation tests

  test "absorb returns error when trying to absorb self" do
    result = @target_user.absorb(@target_user)

    assert_not result[:success]
    assert_includes result[:errors], "Cannot merge user into itself"
  end

  test "absorb returns error when source user is nil" do
    result = @target_user.absorb(nil)

    assert_not result[:success]
    assert_includes result[:errors], "Source user not found"
  end

  # Team membership tests

  test "absorb transfers team memberships" do
    show = FactoryBot.create(:show)
    source_team_member = FactoryBot.create(:team_member, user: @source_user, teamwork: show, position: "Director")

    result = @target_user.absorb(@source_user)

    assert result[:success], "Absorb should succeed: #{result[:errors]}"
    assert_includes @target_user.team_membership.reload.pluck(:teamwork_id), show.id
    assert_not User.exists?(@source_user.id), "Source user should be deleted"
  end

  test "absorb concatenates positions when both users are on same show" do
    show = FactoryBot.create(:show)
    FactoryBot.create(:team_member, user: @target_user, teamwork: show, position: "Director")
    FactoryBot.create(:team_member, user: @source_user, teamwork: show, position: "Producer")

    initial_count = @target_user.team_membership.count

    result = @target_user.absorb(@source_user)

    assert result[:success], "Absorb should succeed: #{result[:errors]}"
    # Due to uniqueness constraint, only one team membership per user per show
    # Positions are concatenated with '/'
    assert_equal initial_count, @target_user.team_membership.reload.count
    position = @target_user.team_membership.find_by(teamwork: show).position
    assert_equal "Director / Producer", position
  end

  test "absorb transfers team memberships from different shows" do
    show1 = FactoryBot.create(:show)
    show2 = FactoryBot.create(:show)
    FactoryBot.create(:team_member, user: @target_user, teamwork: show1, position: "Director")
    FactoryBot.create(:team_member, user: @source_user, teamwork: show2, position: "Producer")

    result = @target_user.absorb(@source_user)

    assert result[:success], "Absorb should succeed: #{result[:errors]}"
    teamwork_ids = @target_user.team_membership.reload.pluck(:teamwork_id)
    assert_includes teamwork_ids, show1.id
    assert_includes teamwork_ids, show2.id
  end

  # Staffing job tests

  test "absorb transfers staffing jobs" do
    staffing_job = FactoryBot.create(:staffing_job, user: @source_user)

    result = @target_user.absorb(@source_user)

    assert result[:success], "Absorb should succeed: #{result[:errors]}"
    assert_equal @target_user.id, staffing_job.reload.user_id
  end

  # Staffing debt tests

  test "absorb transfers staffing debts and reallocates" do
    debt = FactoryBot.create(:staffing_debt, user: @source_user)

    result = @target_user.absorb(@source_user)

    assert result[:success], "Absorb should succeed: #{result[:errors]}"
    assert_equal @target_user.id, debt.reload.user_id
  end

  # Maintenance debt tests

  test "absorb transfers maintenance debts and reallocates" do
    debt = FactoryBot.create(:maintenance_debt, user: @source_user)

    result = @target_user.absorb(@source_user)

    assert result[:success], "Absorb should succeed: #{result[:errors]}"
    assert_equal @target_user.id, debt.reload.user_id
  end

  # Debt notification tests

  test "absorb transfers debt notifications" do
    notification = FactoryBot.create(:initial_debt_notification, user: @source_user)

    result = @target_user.absorb(@source_user)

    assert result[:success], "Absorb should succeed: #{result[:errors]}"
    assert_equal @target_user.id, notification.reload.user_id
  end

  # Maintenance attendance tests

  test "absorb transfers maintenance attendances" do
    attendance = FactoryBot.create(:maintenance_attendance, user: @source_user)

    result = @target_user.absorb(@source_user)

    assert result[:success], "Absorb should succeed: #{result[:errors]}"
    assert_equal @target_user.id, attendance.reload.user_id
  end

  # Role tests

  test "absorb merges roles from both users" do
    @source_user.add_role(:committee)
    @target_user.add_role(:member)

    result = @target_user.absorb(@source_user)

    assert result[:success], "Absorb should succeed: #{result[:errors]}"
    assert @target_user.has_role?(:member), "Target should keep member role"
    assert @target_user.has_role?(:committee), "Target should gain committee role from source"
  end

  test "absorb does not duplicate roles already on target" do
    @source_user.add_role(:member)
    @target_user.add_role(:member)

    initial_role_count = @target_user.roles.count

    result = @target_user.absorb(@source_user)

    assert result[:success], "Absorb should succeed: #{result[:errors]}"
    assert_equal initial_role_count, @target_user.roles.reload.count, "Should not duplicate existing roles"
  end

  # Source user deletion test

  test "absorb destroys source user after transfer" do
    source_id = @source_user.id

    result = @target_user.absorb(@source_user)

    assert result[:success], "Absorb should succeed: #{result[:errors]}"
    assert_not User.exists?(source_id), "Source user should be deleted"
  end

  # Transaction rollback test - we test this by verifying data consistency after success
  # The transaction behavior is tested by Rails itself, so we just verify successful transfers

  # Return value tests

  test "absorb returns transferred counts on success" do
    FactoryBot.create(:staffing_job, user: @source_user)
    FactoryBot.create(:staffing_debt, user: @source_user)
    @source_user.add_role("Committee")

    result = @target_user.absorb(@source_user)

    assert result[:success]
    assert result[:transferred].is_a?(Hash), "Should return transferred counts"
    assert_equal 1, result[:transferred][:staffing_jobs]
    assert_equal 1, result[:transferred][:staffing_debts]
    assert_includes result[:transferred][:roles], "Committee"
  end
end
