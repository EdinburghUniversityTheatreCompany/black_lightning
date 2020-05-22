require 'test_helper'
# Searching is not tested. This can easily be done manually and it cannot be fully tested by unit tests anyway.
class Admin::MaintenanceDebtsControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)

    @maintenance_debt = FactoryBot.create(:maintenance_debt)
  end

  test 'should get index with multiple debts' do
    FactoryBot.create_list(:maintenance_debt, 10)

    get :index
    assert_response :success

    assert_not_nil assigns(:maintenance_debts)
    assert_not assigns(:is_specific_user)
    assert_not assigns(:show_fulfilled)
  end

  # Members can by default only see their own debts.
  test 'should get index for members' do
    other_maintenance_debt = FactoryBot.create(:maintenance_debt)
    sign_in other_maintenance_debt.user

    get :index
    assert_response :success
    assert_equal [other_maintenance_debt], assigns(:maintenance_debts).to_a

    assert assigns(:is_specific_user)
    assert assigns(:show_fulfilled)
  end

  test 'should get index with user ID' do
    FactoryBot.create(:maintenance_debt)

    get :index, params: { user_id: @maintenance_debt.user.id }
    assert_response :success

    assert_equal [@maintenance_debt], assigns(:maintenance_debts).to_a
    assert assigns(:is_specific_user)
    assert assigns(:show_fulfilled)
  end

  test 'should show admin_maintenance_debt' do
    get :show, params: { id: @maintenance_debt }
    assert_response :success
  end

  test 'should get new' do
    FactoryBot.create(:show, start_date: Date.today)
    get :new
    assert_response :success
  end

  test 'should create admin_maintenance_debt' do
    attributes = {
      user_id: FactoryBot.create(:member).id,
      show_id: FactoryBot.create(:show).id,
      due_by: Date.today.advance(days: -1)
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

  test 'should "destroy" admin_maintenance_debt' do
    assert_difference('Admin::MaintenanceDebt.uncompleted.count', -1) do
      assert_no_difference('Admin::MaintenanceDebt.count') do
        delete :destroy, params: { id: @maintenance_debt }
      end
    end

    assert assigns(:maintenance_debt).status == :completed

    assert_redirected_to admin_maintenance_debts_path
  end

  test 'should convert to staffing debt' do
    assert_difference('Admin::MaintenanceDebt.uncompleted.count', -1) do
      assert_no_difference('Admin::MaintenanceDebt.count') do
        assert_difference('Admin::StaffingDebt.count', +1) do
          put :convert_to_staffing_debt, params: { id: @maintenance_debt.id }
        end
      end
    end
    assert(Admin::StaffingDebt.where(user_id: @maintenance_debt.user_id, show_id: @maintenance_debt.show_id).any?, 'There should be a staffing debt with the same details as the old maintenance debt' )
  end
end
