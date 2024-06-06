require 'test_helper'

class Admin::StaffingDebtsControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)

    @staffing_debt = FactoryBot.create(:staffing_debt)
    #@show = FactoryBot.create(:show)
    #@user = FactoryBot.create(:member)
  end

  test 'should get index with multiple debts' do
    FactoryBot.create_list(:staffing_debt, 10)

    get :index
    assert_response :success

    assert_not_nil assigns(:staffing_debts)
    assert_not assigns(:is_specific_user)
  end

  # Members can by default only see their own debts.
  test 'should get index for members' do
    other_staffing_debt = FactoryBot.create(:staffing_debt)
    sign_in other_staffing_debt.user

    get :index
    assert_response :success
    # It should not include the @staffing_debt defined in the setup
    assert_equal [other_staffing_debt], assigns(:staffing_debts).to_a
    assert_not_includes assigns(:staffing_debts), @staffing_debt
    assert assigns(:is_specific_user)
  end

  test 'should get index with user ID' do
    _other_staffing_debt = FactoryBot.create(:staffing_debt)

    get :index, params: { user_id: @staffing_debt.user.id }
    assert_response :success

    assert_equal [@staffing_debt], assigns(:staffing_debts).to_a
    assert assigns(:is_specific_user)
  end

  test 'should get show' do
    # Create some jobs to make sure there are no errors when generating the list
    FactoryBot.create_list(:staffing_job, 5, user: @staffing_debt.user)

    get :show, params: { id: @staffing_debt }

    assert_response :success
  end

  test 'should get new' do
    FactoryBot.create(:show, start_date: Date.current)
    get :new
    assert_response :success
  end

  test 'should create admin_staffing_debt' do
    attributes = {
      user_id: FactoryBot.create(:member).id,
      show_id: FactoryBot.create(:show).id,
      due_by: Date.current.advance(days: -1)
    }
    
    assert_difference('Admin::StaffingDebt.count') do
      post :create, params: { admin_staffing_debt: attributes }
    end

    assert(Admin::StaffingDebt.where(due_by: attributes[:due_by], show_id: attributes[:show_id], user_id: attributes[:user_id]).any?, 'There should be a debt with the details entered')

    assert_redirected_to admin_staffing_debt_path(assigns(:staffing_debt))
  end

  test 'should not create invalid admin_staffing debt' do
    assert_no_difference('Admin::StaffingDebt.count') do
      post :create, params: { admin_staffing_debt: { due_by: nil } }
    end

    assert_response :unprocessable_entity
  end

  test 'should get edit' do
    get :edit, params: { id: @staffing_debt }
    assert_response :success
  end

  test 'should update admin_staffing_debt' do
    attributes = {
      show_id: FactoryBot.create(:show).id,
    }

    assert_no_difference('Admin::StaffingDebt.count') do
      patch :update, params: { id: @staffing_debt, admin_staffing_debt: attributes }
    end

    assert_equal attributes[:show_id], assigns(:staffing_debt).show_id, 'The show id of the staffing debt should equal the new value'
    assert_redirected_to admin_staffing_debt_path(assigns(:staffing_debt))
  end

  test 'should not update invalid admin_staffing debt' do
    patch :update, params: { id: @staffing_debt, admin_staffing_debt: { show_id: nil } }

    assert_response :unprocessable_entity
  end

  test 'should forgive admin_staffing_debt' do
    assert_difference('Admin::StaffingDebt.unfulfilled.count', -1) do
      assert_no_difference('Admin::StaffingDebt.count') do
        put :forgive, params: { id: @staffing_debt }
      end
    end

    assert_equal :forgiven, assigns(:staffing_debt).status

    assert_redirected_to admin_staffing_debts_path
  end

  test 'should assign job to admin_staffing_debt' do
    staffing_job = FactoryBot.create(:staffing_job, user: @staffing_debt.user)

    staffing_job.update_attribute(:staffing_debt, nil)

    other_staffing_debt = FactoryBot.create(:staffing_debt)

    put :assign, params: { id: other_staffing_debt, job_id: staffing_job.id }

    assert_nil flash[:error]
    assert_equal staffing_job, other_staffing_debt.reload.admin_staffing_job
    staffing_job.reload
    assert_equal other_staffing_debt.id, staffing_job.staffing_debt.id
  end

  test 'should unassign job from admin_staffing_debt' do
    staffing_job = FactoryBot.create(:staffing_job, user: @staffing_debt.user)
    staffing_job.update_attribute(:staffing_debt, @staffing_debt)

    assert_equal @staffing_debt.id, staffing_job.reload.staffing_debt&.id

    put :unassign, params: { id: @staffing_debt }

    assert_nil @staffing_debt.reload.admin_staffing_job
    assert_nil staffing_job.reload.staffing_debt
  end
end
