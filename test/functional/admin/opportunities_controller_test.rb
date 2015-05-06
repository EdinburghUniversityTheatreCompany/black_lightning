require 'test_helper'

class Admin::OpportunitiesControllerTest < ActionController::TestCase
  setup do
    sign_in FactoryGirl.create(:admin)
  end

  test 'should get index' do
    FactoryGirl.create_list(:opportunity, 10)

    get :index
    assert_response :success
    assert_not_nil assigns(:opportunities)
  end

  test 'should get show' do
    @opportunity = FactoryGirl.create(:opportunity)

    get :show, id: @opportunity
    assert_response :success
  end

  test 'should get new' do
    get :new
    assert_response :success
  end

  test 'should create opportunity' do
    attrs = FactoryGirl.attributes_for(:opportunity)

    assert_difference('Opportunity.count') do
      post :create, opportunity: attrs
    end

    assert_redirected_to admin_opportunity_path(assigns(:opportunity))
  end

  test 'should get edit' do
    @opportunity = FactoryGirl.create(:opportunity)

    get :edit, id: @opportunity
    assert_response :success
  end

  test 'should update opportunity' do
    @opportunity = FactoryGirl.create(:opportunity)
    attrs = FactoryGirl.attributes_for(:opportunity)

    put :update, id: @opportunity, opportunity: attrs
    assert_redirected_to admin_opportunity_path(assigns(:opportunity))
  end

  test 'should destroy opportunity' do
    @opportunity = FactoryGirl.create(:opportunity)

    assert_difference('Opportunity.count', -1) do
      delete :destroy, id: @opportunity
    end

    assert_redirected_to admin_opportunities_path
  end
end
