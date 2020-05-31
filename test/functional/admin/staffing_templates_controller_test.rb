require 'test_helper'

class Admin::StaffingTemplatesControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)
    @template = FactoryBot.create(:staffing_template, job_count: 5)
  end

  test 'should get index' do
    @template = FactoryBot.create_list(:staffing_template, 5)

    get :index
    assert_response :success
  end

  test 'should get show' do
    get :show, params: { id: @template }
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

    assert_redirected_to admin_staffing_template_path(assigns(:staffing_template))
  end

  test 'should not create invalid staffing_template' do
    attrs = FactoryBot.attributes_for(:staffing_template, name: nil)

    assert_no_difference('Admin::StaffingTemplate.count') do
      post :create, params: { admin_staffing_template: attrs }
    end

    assert_response :unprocessable_entity
  end

  test 'should get edit' do
    get :edit, params: { id: @template }
    assert_response :success
  end

  test 'should update staffing_template' do
    attrs = FactoryBot.attributes_for(:staffing_template)

    put :update, params: { id: @template, admin_staffing_template: attrs }

    assert_redirected_to admin_staffing_template_path(@template)
  end

  test 'should not update invalid staffing_template' do
    attrs = FactoryBot.attributes_for(:staffing_template, name: '')

    put :update, params: { id: @template, admin_staffing_template: attrs }

    assert_response :unprocessable_entity
  end

  test 'should destroy staffing_template' do
    assert_difference('Admin::StaffingTemplate.count', -1) do
      assert_difference('Admin::StaffingJob.count', -@template.staffing_jobs.count) do
        delete :destroy, params: { id: @template }
      end
    end

    assert_redirected_to admin_staffing_templates_path
  end
end
