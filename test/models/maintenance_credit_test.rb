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
  # How debts and credits are matched to each other.

  setup do
    @user = users(:member)
  end

  test "rematch debt if credit is removed and there is a debt that is due later with linked credit" do
    # Once the soonest debt loses its credit, the future debt's credit moves to it; the middle one gets none.
    soonest_debt = FactoryBot.create(:maintenance_debt, user: @user, due_by: Date.current - 1, with_credit: true)
    middle_debt = FactoryBot.create(:maintenance_debt, user: @user, due_by: Date.current, with_credit: false)
    future_debt = FactoryBot.create(:maintenance_debt, user: @user, due_by: Date.current + 1, with_credit: true)

    to_be_transferred_attendance = future_debt.maintenance_credit

    soonest_debt.maintenance_credit.destroy

    assert_equal to_be_transferred_attendance, soonest_debt.reload.maintenance_credit
    assert_nil future_debt.reload.maintenance_credit
    assert_nil middle_debt.reload.maintenance_credit
  end

  test "Match with unmatched credit when debt is added" do
    credit = FactoryBot.create(:maintenance_credit, user: @user)
    debt = FactoryBot.create(:maintenance_debt, with_credit: false, user: @user)

    assert_equal credit, debt.reload.maintenance_credit
  end

  test "Match with credit from future debt when sooner debt is added" do
    future_debt = FactoryBot.create(:maintenance_debt, with_credit: true, user: @user, due_by: Date.current + 2)
    to_be_transferred_attendance = future_debt.maintenance_credit

    sooner_debt = FactoryBot.create(:maintenance_debt, with_credit: false, user: @user, due_by: Date.current)

    assert_equal to_be_transferred_attendance, sooner_debt.reload.maintenance_credit
    assert_nil future_debt.reload.maintenance_credit
  end

  test "match credit from destroyed debt with soonest debt" do
    later_debt = FactoryBot.create(:maintenance_debt, with_credit: false, user: @user, due_by: Date.current + 1)
    soonest_debt = FactoryBot.create(:maintenance_debt, with_credit: false, user: @user, due_by: Date.current)
    debt_with_credit = FactoryBot.create(:maintenance_debt, with_credit: true, user: @user, due_by: Date.current - 1)

    assert_not_nil debt_with_credit.maintenance_credit

    credit = debt_with_credit.maintenance_credit

    debt_with_credit.destroy

    assert_equal credit, soonest_debt.reload.maintenance_credit
    assert_nil later_debt.reload.maintenance_credit
  end

  test "Transfer credit to sooner debt if due_by moves into the future" do
    debt_with_credit = FactoryBot.create(:maintenance_debt, user: @user, with_credit: true, due_by: Date.current)
    credit = debt_with_credit.maintenance_credit

    debt_without_credit = FactoryBot.create(:maintenance_debt, user: @user, with_credit: false, due_by: Date.current + 1)

    assert_not_nil debt_with_credit.reload.maintenance_credit, "The debt_with_credit has no credit matched. debt_without_credit #{debt_without_credit.maintenance_credit.present? ? 'does' : 'does not'} have an credit attached"
    debt_with_credit.update(due_by: Date.current + 5)

    assert_nil debt_with_credit.reload.maintenance_credit
    assert_equal credit, debt_without_credit.reload.maintenance_credit
  end

  test "Do not transfer credit if due date of a debt with credit moves forward." do
    debt_with_credit = FactoryBot.create(:maintenance_debt, user: @user, with_credit: true, due_by: Date.current)
    credit = debt_with_credit.maintenance_credit

    debt_without_credit = FactoryBot.create(:maintenance_debt, user: @user, with_credit: false, due_by: Date.current + 1)

    debt_with_credit.update(due_by: Date.current - 1)

    assert_nil debt_without_credit.reload.maintenance_credit
    assert_equal credit, debt_with_credit.reload.maintenance_credit
  end

  test "Transfer credit from later debt if due_by moves closer" do
    debt_with_credit = FactoryBot.create(:maintenance_debt, user: @user, with_credit: true, due_by: Date.current)
    debt_without_credit = FactoryBot.create(:maintenance_debt, user: @user, with_credit: false, due_by: Date.current + 2)
    credit = debt_with_credit.maintenance_credit

    assert_nil debt_without_credit.reload.maintenance_credit
    assert_not_nil credit

    debt_without_credit.update!(due_by: Date.current - 4)

    assert_equal credit, debt_without_credit.reload.maintenance_credit
    assert_nil debt_with_credit.reload.maintenance_credit
  end

  test "Do not transfer if debt without credit moves further into the future" do
    debt_with_credit = FactoryBot.create(:maintenance_debt, user: @user, with_credit: true, due_by: Date.current)
    debt_without_credit = FactoryBot.create(:maintenance_debt, user: @user, with_credit: false, due_by: Date.current + 2)
    credit = debt_with_credit.maintenance_credit

    debt_without_credit.update(due_by: Date.current + 5)

    assert_equal credit, debt_with_credit.reload.maintenance_credit
    assert_nil debt_without_credit.reload.maintenance_credit
  end

  test "find soonest debt when credit is added" do
    sooner_debt = FactoryBot.create(:maintenance_debt, user: @user, due_by: Date.current + 1)
    later_debt = FactoryBot.create(:maintenance_debt, user: @user, due_by: Date.current + 2)

    credit = FactoryBot.create(:maintenance_credit, user: @user)

    assert_equal credit.reload.maintenance_debt, sooner_debt
    assert_nil later_debt.reload.maintenance_credit
  end

  test "Do not match with credit when there are none available" do
    debt = FactoryBot.create(:maintenance_debt, user: @user, with_credit: false)
    assert_nil debt.maintenance_credit
  end

  test "Free up credit when maintenance debt is destroyed and there are no unmatched debts" do
    debt_with_credit = FactoryBot.create(:maintenance_debt, user: @user, with_credit: true)
    credit = debt_with_credit.maintenance_credit

    debt_with_credit.destroy

    assert_nil credit.reload.maintenance_debt
  end

  test "only match with debt for the same user" do
    debt_for_user = FactoryBot.create(:maintenance_debt, user: @user, due_by: Date.current + 3, with_credit: false)

    # Due sooner, so a matcher ignoring the user would pick it.
    debt_for_other_user = FactoryBot.create(:maintenance_debt, due_by: Date.current + 1, with_credit: false)

    credit = FactoryBot.create(:maintenance_credit, user: @user)

    debt_for_user.reload

    assert_equal debt_for_user, credit.reload.maintenance_debt
    assert_nil debt_for_other_user.reload.maintenance_credit
  end

  test "only takes debt that has normal status" do
    # The converted debt is due sooner, so a matcher ignoring the state would pick it.
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

    assert_nil debt.reload.maintenance_credit
    assert_nil credit.reload.maintenance_debt
  end

  test "converting a debt should release the credit" do
    debt = FactoryBot.create(:maintenance_debt, with_credit: true)
    credit = debt.maintenance_credit

    assert_not_nil credit

    debt.convert_to_staffing_debt

    debt.associate_with_credit

    assert_nil debt.reload.maintenance_credit
    assert_nil credit.reload.maintenance_debt
  end
end
