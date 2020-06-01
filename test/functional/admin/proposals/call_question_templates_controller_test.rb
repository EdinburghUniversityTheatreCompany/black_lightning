require 'test_helper'

class Admin::Proposals::CallQuestionTemplatesControllerTest < ActionController::TestCase
  setup do
    @template = admin_proposals_call_question_templates(:mainterm)

    assert @template.questions.present?

    sign_in users(:admin)
  end

  test 'should get index' do
    get :index
    assert_response :success
    assert_not_nil assigns(:call_question_templates)
  end

  test 'should get show' do
    get :show, params: { id: @template.id }
    assert_response :success
  end

  test 'should get new' do
    get :new
    assert_response :success
  end

  test 'should create admin_proposals_call_question_template' do
    assert_difference('Admin::Proposals::CallQuestionTemplate.count') do
      post :create, params: { admin_proposals_call_question_template: { name: 'Pineapple' } }
    end

    assert_redirected_to admin_proposals_call_question_template_path(assigns(:call_question_template))
  end

  test 'should not create invalid admin_proposals_call_question_template' do
    assert_no_difference('Admin::Proposals::CallQuestionTemplate.count') do
      post :create, params: { admin_proposals_call_question_template: { name: nil } }
    end

    assert_response :unprocessable_entity
  end

  test 'should get edit' do
    get :edit, params: { id: @template.id }
    assert_response :success
  end

  test 'should update admin_proposals_call_question_template' do
    put :update, params: { id: @template, admin_proposals_call_question_template: { name: 'Hexagon' } }

    assert_redirected_to admin_proposals_call_question_template_path(assigns(:call_question_template))
    assert_equal 'Hexagon', assigns(:call_question_template).name
  end

  test 'should not update invalid admin_proposals_call_question_template' do
    put :update, params: { id: @template, admin_proposals_call_question_template: { name: admin_proposals_call_question_templates(:lunchtime).name } }

    assert_response :unprocessable_entity
  end

  test 'should destroy admin_proposals_call_question_template' do
    assert_difference('Admin::Proposals::CallQuestionTemplate.count', -1) do
      delete :destroy, params: { id: @template }
    end

    assert_redirected_to admin_proposals_call_question_templates_path
  end
end
