require 'test_helper'

class Admin::SharedDebtHelperTest < ActionView::TestCase
  def current_ability
    return @current_user.ability
  end

  test 'shared_debt_load' do
    skip 'Would be very nice to also test at some point, but the code is complicated and depends on a lot of variables.'
  end

  test 'shared_debt_search_params' do
    key = 'chocolate'

    assert shared_debt_show_fulfilled_param({ show_fulfilled: '1' }, key)

    assert_equal 'true', cookies["#{key}_show_fulfilled"]

    # Should have stored in a cookie and read that now.
    assert shared_debt_show_fulfilled_param({}, key)

    # Should be able to override it by specifying a param again.
    assert_not shared_debt_show_fulfilled_param({ show_fulfilled: '0' }, key)
  end
  
  test 'shared_debt_show_fulfilled_param' do
    key = 'chocolate'

    assert shared_debt_show_fulfilled_param({ show_fulfilled: '1' }, key)

    assert_equal 'true', cookies["#{key}_show_fulfilled"]

    # Should have stored in a cookie and read that now.
    assert shared_debt_show_fulfilled_param({}, key)

    # Should be able to override it by specifying a param again.
    assert_not shared_debt_show_fulfilled_param({ show_fulfilled: '0' }, key)
  end

  test 'shared_debt_clear_params' do
    key = 'pineapple'

    cookies["#{key}_query"] = 'finbar'
    cookies["#{key}_show_fulfilled"] = 'cyclops'

    shared_debt_clear_params(key)

    assert_nil cookies["#{key}_query"]
    assert_nil cookies["#{key}_show_fulfilled"]
  end

  test 'shared_debt_ransack searches' do
    debt_ids = FactoryBot.create_list(:maintenance_debt, 3).collect(&:id)
    debts = Admin::MaintenanceDebt.where(id: debt_ids)

    q_param = { user_full_name_cont: debts.first.user.name(users(:admin)) }

    q = shared_debt_ransack(debts, q_param)

    assert_includes q.result, debts.first
    assert_not_includes q.result, debts.last.user

    # Testing the sorts is hard, because q.sorts is not just a happy array.
  end

  test 'shared_debt_is_specific_user with user_id' do
    assert_equal [true, true], shared_debt_is_specific_user('Pineapple', 1)
  end

  test 'shared_debt_is_specific_user when user can only read one person\'s debt' do
    staffing_debt = FactoryBot.create(:staffing_debt)
    @current_user = staffing_debt.user
    other_staffing_debt = FactoryBot.create(:staffing_debt)
    
    assert_equal [true, true], shared_debt_is_specific_user(Admin::StaffingDebt, nil)
  end

  test 'shared_debt_is_specific_user returns false when the user can read multiple debts' do
    @current_user = users(:admin)

    staffing_debt = FactoryBot.create_list(:staffing_debt, 2)
    
    assert_equal [false, false], shared_debt_is_specific_user(Admin::StaffingDebt, nil)
  end
end
