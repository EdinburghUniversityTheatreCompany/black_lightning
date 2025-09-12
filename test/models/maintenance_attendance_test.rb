# == Schema Information
#
# Table name: maintenance_attendances
#
# *id*::                     <tt>bigint, not null, primary key</tt>
# *maintenance_session_id*:: <tt>bigint, not null</tt>
# *user_id*::                <tt>integer, not null</tt>
# *created_at*::             <tt>datetime, not null</tt>
# *updated_at*::             <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
require "test_helper"

class MaintenanceAttendanceTest < ActiveSupport::TestCase
  # Most of these tests would fit better on maintenance_debt_test but they are all about the interplay.
  # This helps separate them from the other maintenance_debt tests.

  setup do
    @user = users(:member)
  end

  test "rematch debt if attendance is removed and there is a debt that is due later with linked attendance" do
    # Set up a soon debt and far future debt with attendances.
    # Once the attendance on the soonest debt is removed, the attendance from the future debt should swap over.
    # Middle should remain untouched.
    soonest_debt = FactoryBot.create(:maintenance_debt, user: @user, due_by: Date.current - 1, with_attendance: true)
    middle_debt = FactoryBot.create(:maintenance_debt, user: @user, due_by: Date.current, with_attendance: false)
    future_debt = FactoryBot.create(:maintenance_debt, user: @user, due_by: Date.current + 1, with_attendance: true)

    to_be_transferred_attendance = future_debt.maintenance_attendance

    # Destroy the attendance on the future debt
    soonest_debt.maintenance_attendance.destroy

    # Make sure that the sooner debt gets the attendance transferred.
    assert_equal to_be_transferred_attendance, soonest_debt.reload.maintenance_attendance
    assert_nil future_debt.reload.maintenance_attendance
    assert_nil middle_debt.reload.maintenance_attendance
  end

  test "Match with unmatched attendance when debt is added" do
    # Create an attendance, then create a debt, and ensure they are matched.
    attendance = FactoryBot.create(:maintenance_attendance, user: @user)
    debt = FactoryBot.create(:maintenance_debt, with_attendance: false, user: @user)

    assert_equal attendance, debt.reload.maintenance_attendance
  end

  test "Match with attendance from future debt when sooner debt is added" do
    # Create a future debt with an attendance
    future_debt = FactoryBot.create(:maintenance_debt, with_attendance: true, user: @user, due_by: Date.current + 2)
    to_be_transferred_attendance = future_debt.maintenance_attendance

    # Create a new, sooner, maintenance_debt.
    sooner_debt = FactoryBot.create(:maintenance_debt, with_attendance: false, user: @user, due_by: Date.current)

    # Check the attendance transfers
    assert_equal to_be_transferred_attendance, sooner_debt.reload.maintenance_attendance
    assert_nil future_debt.reload.maintenance_attendance
  end

  test "match attendance from destroyed debt with soonest debt" do
    later_debt = FactoryBot.create(:maintenance_debt, with_attendance: false, user: @user, due_by: Date.current + 1)
    soonest_debt = FactoryBot.create(:maintenance_debt, with_attendance: false, user: @user, due_by: Date.current)
    debt_with_attendance = FactoryBot.create(:maintenance_debt, with_attendance: true, user: @user, due_by: Date.current - 1)

    # Make sure the attendance has not cheekily aligned itself with a different debt.
    assert_not_nil debt_with_attendance.maintenance_attendance

    attendance = debt_with_attendance.maintenance_attendance

    debt_with_attendance.destroy

    # Test the attendance transferred to the soonest dent
    assert_equal attendance, soonest_debt.reload.maintenance_attendance
    assert_nil later_debt.reload.maintenance_attendance
  end

  # In this test the debt_with_attendance is moved and the attendance should move away from it.
  test "Transfer attendance to sooner debt if due_by moves into the future" do
    debt_with_attendance = FactoryBot.create(:maintenance_debt, user: @user, with_attendance: true, due_by: Date.current)
    attendance = debt_with_attendance.maintenance_attendance

    debt_without_attendance = FactoryBot.create(:maintenance_debt, user: @user, with_attendance: false, due_by: Date.current + 1)

    assert_not_nil debt_with_attendance.reload.maintenance_attendance, "The debt_with_attendance has no attendance matched. debt_without_attendance #{debt_without_attendance.maintenance_attendance.present? ? 'does' : 'does not'} have an attendance attached"
    # Change the date on the debt with attendance so that it is due after the other debt. The attendance should then move.
    debt_with_attendance.update(due_by: Date.current + 5)

    assert_nil debt_with_attendance.reload.maintenance_attendance
    assert_equal attendance, debt_without_attendance.reload.maintenance_attendance
  end

  test "Do not transfer attendance if due date of a debt with attendance moves forward." do
    debt_with_attendance = FactoryBot.create(:maintenance_debt, user: @user, with_attendance: true, due_by: Date.current)
    attendance = debt_with_attendance.maintenance_attendance

    debt_without_attendance = FactoryBot.create(:maintenance_debt, user: @user, with_attendance: false, due_by: Date.current + 1)

    # Update debt_with_attendance to happen earlier
    debt_with_attendance.update(due_by: Date.current - 1)

    # Assert nothing changed.
    assert_nil debt_without_attendance.reload.maintenance_attendance
    assert_equal attendance, debt_with_attendance.reload.maintenance_attendance
  end

  # In this test, the debt without attendance is moved and the
  test "Transfer attendance from later debt if due_by moves closer" do
    debt_with_attendance = FactoryBot.create(:maintenance_debt, user: @user, with_attendance: true, due_by: Date.current)
    debt_without_attendance = FactoryBot.create(:maintenance_debt, user: @user, with_attendance: false, due_by: Date.current + 2)
    attendance = debt_with_attendance.maintenance_attendance

    assert_nil debt_without_attendance.reload.maintenance_attendance
    assert_not_nil attendance

    # Move the debt_without_attendance to before debt_with_attendance, and check if it got the attendance.
    debt_without_attendance.update!(due_by: Date.current - 4)

    assert_equal attendance, debt_without_attendance.reload.maintenance_attendance
    assert_nil debt_with_attendance.reload.maintenance_attendance
  end

  test "Do not transfer if debt without attendance moves further into the future" do
    debt_with_attendance = FactoryBot.create(:maintenance_debt, user: @user, with_attendance: true, due_by: Date.current)
    debt_without_attendance = FactoryBot.create(:maintenance_debt, user: @user, with_attendance: false, due_by: Date.current + 2)
    attendance = debt_with_attendance.maintenance_attendance

    # Update debt_without_attendance to happen further into the future than currently.
    debt_without_attendance.update(due_by: Date.current + 5)

    # Assert nothing changed.
    assert_equal attendance, debt_with_attendance.reload.maintenance_attendance
    assert_nil debt_without_attendance.reload.maintenance_attendance
  end

  test "find soonest debt when attendance is added" do
    # Create two debts with different due dates.
    sooner_debt = FactoryBot.create(:maintenance_debt, user: @user, due_by: Date.current + 1)
    later_debt = FactoryBot.create(:maintenance_debt, user: @user, due_by: Date.current + 2)

    attendance = FactoryBot.create(:maintenance_attendance, user: @user)

    # Assert the maintenance matched to the sooner debt and not the later.
    assert_equal attendance.reload.maintenance_debt, sooner_debt
    assert_nil later_debt.reload.maintenance_attendance
  end

  ##
  # Failsafe tests
  ##

  # Just test that this case works, and that it does not associate with an attendance from somewhere else.
  # If it does associate with a debt from somewhere else, that could break the other tests.
  test "Do not match with attendance when there are none available" do
    debt = FactoryBot.create(:maintenance_debt, user: @user, with_attendance: false)
    assert_nil debt.maintenance_attendance
  end

  # If this test fails, there might be some rogue maintenance debts.
  test "Free up attendance when maintenance debt is destroyed and there are no unmatched debts" do
    debt_with_attendance = FactoryBot.create(:maintenance_debt, user: @user, with_attendance: true)
    attendance = debt_with_attendance.maintenance_attendance

    # Destroy the debt.
    debt_with_attendance.destroy

    # Check that the attendance no longer has a maintenance debt associated with it
    assert_nil attendance.reload.maintenance_debt
  end

  test "only match with debt for the same user" do
    debt_for_user = FactoryBot.create(:maintenance_debt, user: @user, due_by: Date.current + 3, with_attendance: false)

    # Earlier due so that it should want to match with this one if it does not take the user into account
    debt_for_other_user = FactoryBot.create(:maintenance_debt, due_by: Date.current + 1, with_attendance: false)

    attendance = FactoryBot.create(:maintenance_attendance, user: @user)

    debt_for_user.reload

    assert_equal debt_for_user, attendance.reload.maintenance_debt
    assert_nil debt_for_other_user.reload.maintenance_attendance
  end

  test "only takes debt that has normal status" do
    # Create a debt that can be matched with with a later due_by so that if it disregards status, it should pick the wrong debt.
    debt_with_normal_state = FactoryBot.create(:maintenance_debt, user: @user, state: 0, due_by: Date.current + 5)
    debt_with_other_state = FactoryBot.create(:maintenance_debt, user: @user, state: 1, due_by: Date.current + 1)

    attendance = FactoryBot.create(:maintenance_attendance, user: @user)

    assert_equal debt_with_normal_state, attendance.maintenance_debt
    assert_nil debt_with_other_state.reload.maintenance_attendance
  end

  test "forgiving a debt should release the attendance" do
    debt = FactoryBot.create(:maintenance_debt, with_attendance: true)
    attendance = debt.maintenance_attendance

    debt.forgive

    # Assert they are not linked with anything.
    assert_nil debt.reload.maintenance_attendance
    assert_nil attendance.reload.maintenance_debt
  end

  test "converting a debt should release the attendance" do
    debt = FactoryBot.create(:maintenance_debt, with_attendance: true)
    attendance = debt.maintenance_attendance

    assert_not_nil attendance

    debt.convert_to_staffing_debt

    debt.associate_with_attendance

    # Assert they are not linked with anything.
    assert_nil debt.reload.maintenance_attendance
    assert_nil attendance.reload.maintenance_debt
  end
end
