require 'test_helper'

class Admin::StaffingJobsControllerTest < ActionController::TestCase
  setup do
    @admin_staffing_job = admin_staffing_jobs(:one)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:admin_staffing_jobs)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create admin_staffing_job" do
    assert_difference('Admin::StaffingJob.count') do
      post :create, admin_staffing_job: {  }
    end

    assert_redirected_to admin_staffing_job_path(assigns(:admin_staffing_job))
  end

  test "should show admin_staffing_job" do
    get :show, id: @admin_staffing_job
    assert_response :success
  end

  test "should get edit" do
    get :edit, id: @admin_staffing_job
    assert_response :success
  end

  test "should update admin_staffing_job" do
    put :update, id: @admin_staffing_job, admin_staffing_job: {  }
    assert_redirected_to admin_staffing_job_path(assigns(:admin_staffing_job))
  end

  test "should destroy admin_staffing_job" do
    assert_difference('Admin::StaffingJob.count', -1) do
      delete :destroy, id: @admin_staffing_job
    end

    assert_redirected_to admin_staffing_jobs_path
  end
end
