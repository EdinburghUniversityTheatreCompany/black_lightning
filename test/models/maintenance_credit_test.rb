# == Schema Information
#
# Table name: maintenance_credits
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

class MaintenanceCreditTest < ActiveSupport::TestCase
  # Most of these tests would fit better on maintenance_debt_test but they are all about the interplay.
  # This helps separate them from the other maintenance_debt tests.

  setup do
    @user = users(:member)
  end

  test "rematch debt if credit is removed and there is a debt that is due later with linked credit" do
    # Set up a soon debt and far future debt with attendances.
    # Once the credit on the soonest debt is removed, the credit from the future debt should swap over.
    # Middle should remain untouched.
    soonest_debt = FactoryBot.create(:maintenance_debt, user: @user, due_by: Date.current - 1, with_credit: true)
    middle_debt = FactoryBot.create(:maintenance_debt, user: @user, due_by: Date.current, with_credit: false)
    future_debt = FactoryBot.create(:maintenance_debt, user: @user, due_by: Date.current + 1, with_credit: true)

    to_be_transferred_attendance = future_debt.maintenance_credit

    # Destroy the credit on the future debt
    soonest_debt.maintenance_credit.destroy

    # Make sure that the sooner debt gets the credit transferred.
    assert_equal to_be_transferred_attendance, soonest_debt.reload.maintenance_credit
    assert_nil future_debt.reload.maintenance_credit
    assert_nil middle_debt.reload.maintenance_credit
  end

  test "Match with unmatched credit when debt is added" do
    # Create an credit, then create a debt, and ensure they are matched.
    credit = FactoryBot.create(:maintenance_credit, user: @user)
    debt = FactoryBot.create(:maintenance_debt, with_credit: false, user: @user)

    assert_equal credit, debt.reload.maintenance_credit
  end

  test "Match with credit from future debt when sooner debt is added" do
    # Create a future debt with an credit
    future_debt = FactoryBot.create(:maintenance_debt, with_credit: true, user: @user, due_by: Date.current + 2)
    to_be_transferred_attendance = future_debt.maintenance_credit

    # Create a new, sooner, maintenance_debt.
    sooner_debt = FactoryBot.create(:maintenance_debt, with_credit: false, user: @user, due_by: Date.current)

    # Check the credit transfers
    assert_equal to_be_transferred_attendance, sooner_debt.reload.maintenance_credit
    assert_nil future_debt.reload.maintenance_credit
  end

  test "match credit from destroyed debt with soonest debt" do
    later_debt = FactoryBot.create(:maintenance_debt, with_credit: false, user: @user, due_by: Date.current + 1)
    soonest_debt = FactoryBot.create(:maintenance_debt, with_credit: false, user: @user, due_by: Date.current)
    debt_with_credit = FactoryBot.create(:maintenance_debt, with_credit: true, user: @user, due_by: Date.current - 1)

    # Make sure the credit has not cheekily aligned itself with a different debt.
    assert_not_nil debt_with_credit.maintenance_credit

    credit = debt_with_credit.maintenance_credit

    debt_with_credit.destroy

    # Test the credit transferred to the soonest dent
    assert_equal credit, soonest_debt.reload.maintenance_credit
    assert_nil later_debt.reload.maintenance_credit
  end

  # In this test the debt_with_credit is moved and the credit should move away from it.
  test "Transfer credit to sooner debt if due_by moves into the future" do
    debt_with_credit = FactoryBot.create(:maintenance_debt, user: @user, with_credit: true, due_by: Date.current)
    credit = debt_with_credit.maintenance_credit

    debt_without_credit = FactoryBot.create(:maintenance_debt, user: @user, with_credit: false, due_by: Date.current + 1)

    assert_not_nil debt_with_credit.reload.maintenance_credit, "The debt_with_credit has no credit matched. debt_without_credit #{debt_without_credit.maintenance_credit.present? ? 'does' : 'does not'} have an credit attached"
    # Change the date on the debt with credit so that it is due after the other debt. The credit should then move.
    debt_with_credit.update(due_by: Date.current + 5)

    assert_nil debt_with_credit.reload.maintenance_credit
    assert_equal credit, debt_without_credit.reload.maintenance_credit
  end

  test "Do not transfer credit if due date of a debt with credit moves forward." do
    debt_with_credit = FactoryBot.create(:maintenance_debt, user: @user, with_credit: true, due_by: Date.current)
    credit = debt_with_credit.maintenance_credit

    debt_without_credit = FactoryBot.create(:maintenance_debt, user: @user, with_credit: false, due_by: Date.current + 1)

    # Update debt_with_credit to happen earlier
    debt_with_credit.update(due_by: Date.current - 1)

    # Assert nothing changed.
    assert_nil debt_without_credit.reload.maintenance_credit
    assert_equal credit, debt_with_credit.reload.maintenance_credit
  end

  # In this test, the debt without credit is moved and the
  test "Transfer credit from later debt if due_by moves closer" do
    debt_with_credit = FactoryBot.create(:maintenance_debt, user: @user, with_credit: true, due_by: Date.current)
    debt_without_credit = FactoryBot.create(:maintenance_debt, user: @user, with_credit: false, due_by: Date.current + 2)
    credit = debt_with_credit.maintenance_credit

    assert_nil debt_without_credit.reload.maintenance_credit
    assert_not_nil credit

    # Move the debt_without_credit to before debt_with_credit, and check if it got the credit.
    debt_without_credit.update!(due_by: Date.current - 4)

    assert_equal credit, debt_without_credit.reload.maintenance_credit
    assert_nil debt_with_credit.reload.maintenance_credit
  end

  test "Do not transfer if debt without credit moves further into the future" do
    debt_with_credit = FactoryBot.create(:maintenance_debt, user: @user, with_credit: true, due_by: Date.current)
    debt_without_credit = FactoryBot.create(:maintenance_debt, user: @user, with_credit: false, due_by: Date.current + 2)
    credit = debt_with_credit.maintenance_credit

    # Update debt_without_credit to happen further into the future than currently.
    debt_without_credit.update(due_by: Date.current + 5)

    # Assert nothing changed.
    assert_equal credit, debt_with_credit.reload.maintenance_credit
    assert_nil debt_without_credit.reload.maintenance_credit
  end

  test "find soonest debt when credit is added" do
    # Create two debts with different due dates.
    sooner_debt = FactoryBot.create(:maintenance_debt, user: @user, due_by: Date.current + 1)
    later_debt = FactoryBot.create(:maintenance_debt, user: @user, due_by: Date.current + 2)

    credit = FactoryBot.create(:maintenance_credit, user: @user)

    # Assert the maintenance matched to the sooner debt and not the later.
    assert_equal credit.reload.maintenance_debt, sooner_debt
    assert_nil later_debt.reload.maintenance_credit
  end

  ##
  # Failsafe tests
  ##

  # Just test that this case works, and that it does not associate with an credit from somewhere else.
  # If it does associate with a debt from somewhere else, that could break the other tests.
  test "Do not match with credit when there are none available" do
    debt = FactoryBot.create(:maintenance_debt, user: @user, with_credit: false)
    assert_nil debt.maintenance_credit
  end

  # If this test fails, there might be some rogue maintenance debts.
  test "Free up credit when maintenance debt is destroyed and there are no unmatched debts" do
    debt_with_credit = FactoryBot.create(:maintenance_debt, user: @user, with_credit: true)
    credit = debt_with_credit.maintenance_credit

    # Destroy the debt.
    debt_with_credit.destroy

    # Check that the credit no longer has a maintenance debt associated with it
    assert_nil credit.reload.maintenance_debt
  end

  test "only match with debt for the same user" do
    debt_for_user = FactoryBot.create(:maintenance_debt, user: @user, due_by: Date.current + 3, with_credit: false)

    # Earlier due so that it should want to match with this one if it does not take the user into account
    debt_for_other_user = FactoryBot.create(:maintenance_debt, due_by: Date.current + 1, with_credit: false)

    credit = FactoryBot.create(:maintenance_credit, user: @user)

    debt_for_user.reload

    assert_equal debt_for_user, credit.reload.maintenance_debt
    assert_nil debt_for_other_user.reload.maintenance_credit
  end

  test "only takes debt that has normal status" do
    # Create a debt that can be matched with with a later due_by so that if it disregards status, it should pick the wrong debt.
    debt_with_normal_state = FactoryBot.create(:maintenance_debt, user: @user, state: 0, due_by: Date.current + 5)
    debt_with_other_state = FactoryBot.create(:maintenance_debt, user: @user, state: 1, due_by: Date.current + 1)

    credit = FactoryBot.create(:maintenance_credit, user: @user)

    assert_equal debt_with_normal_state, credit.maintenance_debt
    assert_nil debt_with_other_state.reload.maintenance_credit
  end

  test "forgiving a debt should release the credit" do
    debt = FactoryBot.create(:maintenance_debt, with_credit: true)
    credit = debt.maintenance_credit

    debt.forgive

    # Assert they are not linked with anything.
    assert_nil debt.reload.maintenance_credit
    assert_nil credit.reload.maintenance_debt
  end

  test "converting a debt should release the credit" do
    debt = FactoryBot.create(:maintenance_debt, with_credit: true)
    credit = debt.maintenance_credit

    assert_not_nil credit

    debt.convert_to_staffing_debt

    debt.associate_with_credit

    # Assert they are not linked with anything.
    assert_nil debt.reload.maintenance_credit
    assert_nil credit.reload.maintenance_debt
  end
end
