require 'test_helper'

class Admin::FaultReportsControllerTest < ActionController::TestCase
  setup do
    sign_in FactoryBot.create(:admin)
  end

  test 'should get index' do
    FactoryBot.create_list(:fault_report, 10)

    get :index
    assert_response :success

    assert_not_nil assigns(:fault_reports)
  end

  test 'should get show' do
    fault_report = FactoryBot.create(:fault_report)

    get :show, params: { id: fault_report.id }
    assert_response :success

    assert_equal fault_report, assigns(:fault_report)
    assert_includes assigns(:title), fault_report.item
  end

  test 'should get new' do
    get :new
    assert_response :success
  end

  test 'should get edit' do
    fault_report = FactoryBot.create(:fault_report)

    get :edit, params: { id: fault_report }
    assert_response :success

    assert_equal fault_report, assigns(:fault_report)
    assert_includes assigns(:title), fault_report.item
  end

  test 'should create fault_report' do
    fault_report_attributes = FactoryBot.attributes_for(:fault_report)

    assert_difference('FaultReport.count') do
      post :create, params: { fault_report: fault_report_attributes }
    end

    assert_redirected_to admin_fault_report_path(assigns(:fault_report))
  end

  test 'should create fault_report without read rights' do

  end

  test 'should update fault_report' do
    fault_report = FactoryBot.create(:fault_report)
    attributes = FactoryBot.attributes_for(:fault_report)

    put :update, params: { id: fault_report, fault_report: attributes }
    assert_redirected_to admin_fault_report_path(assigns(:fault_report))
  end

  test 'should destroy admin_feedback' do
    fault_report = FactoryBot.create(:fault_report)

    assert_difference('FaultReport.count', -1) do
      delete :destroy, params: { id: fault_report }
    end

    assert_redirected_to admin_fault_reports_path
  end
end