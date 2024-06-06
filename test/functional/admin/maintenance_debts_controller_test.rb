require 'test_helper'
# Searching is not tested. This can easily be done manually and it cannot be fully tested by unit tests anyway.
class Admin::MaintenanceDebtsControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)

    @maintenance_debt = FactoryBot.create(:maintenance_debt)
  end

  test 'should get index with multiple debts' do
    debts = FactoryBot.create_list(:maintenance_debt, 4)

    # Debts by default are assigned to members, so we set one to a non-member,
    # and make sure that the index does not include it.
    non_member_debt = debts.first
    non_member_debt.user.remove_role(:member)

    get :index
    assert_response :success

    assert_not_nil assigns(:maintenance_debts)
    assert_not assigns(:is_specific_user)

    # Ensure only non-members are included in the index.
    assert assigns(:maintenance_debts).all { |debt| debt.user.has_role?(:member) }, 'The index includes a few non_members'
    assert_not_includes assigns(:maintenance_debts), non_member_debt, 'The index includes a non_member'
  end

  test 'should get index with non-member debts' do
    debts = FactoryBot.create_list(:maintenance_debt, 2)

    # Debts by default are assigned to members, so we set one to a non-member,
    # and make sure that the index does not include it.
    non_member_debt = debts.first
    non_member_debt.user.remove_role(:member)

    get :index, params: { show_non_members: '1' }
    assert_response :success

    assert_not_nil assigns(:maintenance_debts)
    assert_not assigns(:is_specific_user)

    # Ensure all debts are included in the index. There is one created before each test, hence the +1.
    assert_equal debts.count + 1, assigns(:maintenance_debts).count, 'The index does not include all debts'
    assert_includes assigns(:maintenance_debts), non_member_debt, 'The index does not includes the non_member'
  end

  # Members can by default only see their own debts.
  test 'should get index for members' do
    other_maintenance_debt = FactoryBot.create(:maintenance_debt)
    sign_in other_maintenance_debt.user

    get :index
    assert_response :success
    assert_equal [other_maintenance_debt], assigns(:maintenance_debts).to_a

    assert assigns(:is_specific_user)
  end

  test 'should get index with user ID' do
    FactoryBot.create(:maintenance_debt)

    get :index, params: { user_id: @maintenance_debt.user.id }
    assert_response :success

    assert_equal [@maintenance_debt], assigns(:maintenance_debts).to_a
    assert assigns(:is_specific_user)
  end

  test 'should show admin_maintenance_debt' do
    get :show, params: { id: @maintenance_debt }
    assert_response :success
  end

  test 'should get new' do
    FactoryBot.create(:show, start_date: Date.current)
    get :new
    assert_response :success
  end

  test 'should create admin_maintenance_debt' do
    attributes = {
      user_id: FactoryBot.create(:member).id,
      show_id: FactoryBot.create(:show).id,
      due_by: Date.current.advance(days: -1)
    }

    assert_difference('Admin::MaintenanceDebt.count') do
      post :create, params: { admin_maintenance_debt: attributes }
    end
    assert(Admin::MaintenanceDebt.where(due_by: attributes[:due_by], show_id: attributes[:show_id], user_id: attributes[:user_id]).any?, 'There should be a debt with the details entered')

    assert_redirected_to admin_maintenance_debt_path(assigns(:maintenance_debt))
  end

  test 'should not create invalid admin_maintenance debt' do
    assert_no_difference('Admin::MaintenanceDebt.count') do
      post :create, params: { admin_maintenance_debt: { user_id: nil } }
    end

    assert_response :unprocessable_entity
  end

  test 'should get edit' do
    get :edit, params: { id: @maintenance_debt }
    assert_response :success
  end

  test 'should update admin_maintenance_debt' do
    new_show = FactoryBot.create(:show)

    patch :update, params: { id: @maintenance_debt, admin_maintenance_debt: { show_id: new_show.id } }

    assert_equal new_show.id, assigns(:maintenance_debt).show_id, 'The show id of the maintenance debt should equal the new value'
    assert_redirected_to admin_maintenance_debt_path(assigns(:maintenance_debt))
  end

  test 'should not update invalid admin_maintenance debt' do
    patch :update, params: { id: @maintenance_debt, admin_maintenance_debt: { due_by: nil } }

    assert_response :unprocessable_entity
  end

  test 'should forgive admin_maintenance_debt' do
    assert_difference('Admin::MaintenanceDebt.unfulfilled.count', -1) do
      assert_no_difference('Admin::MaintenanceDebt.count') do
        put :forgive, params: { id: @maintenance_debt }
      end
    end

    assert assigns(:maintenance_debt).status == :forgiven

    assert_redirected_to admin_maintenance_debts_path
  end

  test 'should convert to staffing debt' do
    assert_difference('Admin::MaintenanceDebt.unfulfilled.count', -1) do
      assert_no_difference('Admin::MaintenanceDebt.count') do
        assert_difference('Admin::StaffingDebt.count', +1) do
          put :convert_to_staffing_debt, params: { id: @maintenance_debt.id }
        end
      end
    end

    new_staffing_debt = Admin::StaffingDebt.where(user_id: @maintenance_debt.user_id, show_id: @maintenance_debt.show_id).first
    assert_not_nil new_staffing_debt, 'There should be a staffing debt with the same details as the old maintenance debt'
    assert new_staffing_debt.converted_from_maintenance_debt, 'The new staffing debt should be converted from a maintenance debt'
    
    assert_redirected_to admin_maintenance_debts_url
  end
end
