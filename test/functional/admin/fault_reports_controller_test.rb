require "test_helper"
require "benchmark"

class Admin::FaultReportsControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)
    @fault_report = FactoryBot.create(:fault_report)
  end

  test "should get index" do
    FactoryBot.create_list(:fault_report, 10)

    get :index
    assert_response :success

    assert_not_nil assigns(:fault_reports)
  end

  test "should get show" do
    get :show, params: { id: @fault_report.id }
    assert_response :success

    assert_equal @fault_report, assigns(:fault_report)
    assert_includes assigns(:title), @fault_report.item
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should get edit" do
    get :edit, params: { id: @fault_report }
    assert_response :success

    assert_equal @fault_report, assigns(:fault_report)
  end

  test "should create fault_report" do
    attributes = FactoryBot.attributes_for(:fault_report)

    assert_difference("FaultReport.count") do
      post :create, params: { fault_report: attributes }
    end

    assert_redirected_to admin_fault_report_path(assigns(:fault_report))
  end

  test "should not create fault_report that is invalid" do
    attributes = FactoryBot.attributes_for(:fault_report, description: "")

    assert_no_difference("FaultReport.count") do
      post :create, params: { fault_report: attributes }
    end

    assert_response :unprocessable_entity
  end

  test "should update fault_report" do
    attributes = FactoryBot.attributes_for(:fault_report)

    put :update, params: { id: @fault_report, fault_report: attributes }
    assert_equal attributes[:item], assigns(:fault_report).item
    assert_redirected_to admin_fault_report_path(assigns(:fault_report))
  end

  test "should not update fault_report that is invalid" do
    attributes = FactoryBot.attributes_for(:fault_report, description: "")

    put :update, params: { id: @fault_report, fault_report: attributes }

    assert_response :unprocessable_entity
  end

  test "should destroy fault_report" do
    assert_difference("FaultReport.count", -1) do
      delete :destroy, params: { id: @fault_report }
    end

    assert_redirected_to admin_fault_reports_path
  end
end
