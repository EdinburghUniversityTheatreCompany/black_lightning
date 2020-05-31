require 'test_helper'

class Admin::Proposals::CallsControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)

    @call = FactoryBot.create :proposal_call
  end

  test 'should get index' do
    FactoryBot.create_list(:proposal_call, 10)

    get :index
    assert_response :success
    assert_not_nil assigns(:calls)
  end

  test 'should show call' do
    get :show, params: { id: @call }
    assert_response :success
  end

  test 'should get new' do
    get :new
    assert_response :success
  end

  test 'should create call' do
    attributes = FactoryBot.attributes_for(:proposal_call)

    assert_difference('Admin::Proposals::Call.count') do
      post :create, params: { admin_proposals_call: attributes }
    end

    assert_redirected_to admin_proposals_call_path(assigns(:call))
  end

  test 'should not create invalid call' do
    attributes = FactoryBot.attributes_for(:proposal_call, editing_deadline: nil)

    assert_no_difference('Admin::Proposals::Call.count') do
      post :create, params: { admin_proposals_call: attributes }
    end

    assert_response :unprocessable_entity
  end

  test 'should get edit' do
    get :edit, params: { id: @call }

    assert_response :success
  end

  test 'should update call' do
    attributes = FactoryBot.attributes_for(:proposal_call, question_count: 3)

    put :update, params: { id: @call, admin_proposals_call: attributes }

    assert_redirected_to admin_proposals_call_path(assigns(:call))
  end

  test 'should not update invalid call' do
    attributes = FactoryBot.attributes_for(:proposal_call, name: nil, question_count: 3)

    put :update, params: { id: @call, admin_proposals_call: attributes }

    assert_response :unprocessable_entity
  end

  test 'should destroy call' do
    @call.proposals.clear

    assert_difference('Admin::Proposals::Call.count', -1) do
      delete :destroy, params: { id: @call }
    end

    assert_redirected_to admin_proposals_calls_path
  end

  test 'should archive call' do
    @call.update_attribute(:editing_deadline, DateTime.now.advance(days: -1))
    @call.update_attribute(:archived, false)

    assert_no_difference('Admin::Proposals::Call.count') do
      put :archive, params: { id: @call }
    end

    assert assigns(:call).archived

    assert_redirected_to admin_proposals_calls_path
  end

  test 'should not archive call with an editing deadline in the future.' do
    @call.update_attribute(:editing_deadline, DateTime.now.advance(days: 1))
    @call.update_attribute(:archived, false)

    assert_no_difference('Admin::Proposals::Call.count') do
      put :archive, params: { id: @call }
    end

    assert_not assigns(:call).archived

    assert_redirected_to admin_proposals_calls_path
  end
end
