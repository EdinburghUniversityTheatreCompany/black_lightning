require 'test_helper'

class Admin::StaffingTemplatesControllerTest < ActionController::TestCase
  setup do
    sign_in FactoryBot.create(:admin)
  end

  test 'should get index' do
    @template = FactoryBot.create_list(:staffing_template, 5)

    get :index
    assert_response :success
  end

  test 'should get show' do
    @template = FactoryBot.create(:staffing_template, job_count: 5)

    get :show, params: { id: @template}
    assert_response :success
  end

  test 'should get new' do
    get :new
    assert_response :success
  end

  test 'should create staffing_template' do
    attrs = FactoryBot.attributes_for(:staffing_template)

    assert_difference('Admin::StaffingTemplate.count') do
      post :create, params: { admin_staffing_template: attrs }
    end

    assert_redirected_to admin_staffing_template_path(assigns(:template))
  end

  test 'should get edit' do
    @template = FactoryBot.create(:staffing_template, job_count: 5)

    get :edit, params: { id: @template}
    assert_response :success
  end

  test 'should update staffing_template' do
    @template = FactoryBot.create(:staffing_template, job_count: 5)
    attrs = FactoryBot.attributes_for(:staffing_template)

    put :update, params: {id: @template, admin_staffing_template: attrs}
    assert_redirected_to admin_staffing_template_path(@template)
  end

  test 'should destroy staffing_template' do
    @template = FactoryBot.create(:staffing_template, job_count: 5)

    assert_difference('Admin::StaffingTemplate.count', -1) do
      assert_difference('Admin::StaffingJob.count', -5) do
        delete :destroy, params: { id: @template}
      end
    end

    assert_redirected_to admin_staffing_templates_path
  end
end
