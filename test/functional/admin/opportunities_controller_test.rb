require 'test_helper'

class Admin::OpportunitiesControllerTest < ActionController::TestCase
  setup do
    sign_in FactoryBot.create(:admin)
  end

  test 'should get index' do
    FactoryBot.create_list(:opportunity, 10)

    get :index
    assert_response :success
    assert_not_nil assigns(:opportunities)
  end

  test 'should get show' do
    @opportunity = FactoryBot.create(:opportunity)

    get :show, params: { id: @opportunity}
    assert_response :success
  end

  test 'should get new' do
    get :new
    assert_response :success
  end

  test 'should create opportunity' do
    attrs = FactoryBot.attributes_for(:opportunity)

    assert_difference('Opportunity.count') do
      post :create, opportunity: attrs
    end

    assert_redirected_to admin_opportunity_path(assigns(:opportunity))
  end

  test 'should get edit' do
    @opportunity = FactoryBot.create(:opportunity)

    get :edit, params: { id: @opportunity}
    assert_response :success
  end

  test 'should update opportunity' do
    @opportunity = FactoryBot.create(:opportunity)
    attrs = FactoryBot.attributes_for(:opportunity)

    put :update, params: {id: @opportunity, opportunity: attrs}
    assert_redirected_to admin_opportunity_path(assigns(:opportunity))
  end

  test 'should destroy opportunity' do
    @opportunity = FactoryBot.create(:opportunity)

    assert_difference('Opportunity.count', -1) do
      delete :destroy, params: { id: @opportunity}
    end

    assert_redirected_to admin_opportunities_path
  end
end
