require 'test_helper'

class Admin::WorkshopsControllerTest < ActionController::TestCase
  setup do
    sign_in FactoryBot.create(:admin)
  end

  test 'should get index' do
    FactoryBot.create_list(:workshop, 10)

    get :index
    assert_response :success
    assert_not_nil assigns(:workshops)
  end

  test 'should get show' do
    @workshop = FactoryBot.create(:workshop)

    get :show, params: { id: @workshop}
    assert_response :success
  end

  test 'should get new' do
    get :new
    assert_response :success
  end

  test 'should create workshop' do
    attrs = FactoryBot.attributes_for(:workshop)

    assert_difference('Workshop.count') do
      post :create, workshop: attrs
    end

    assert_redirected_to admin_workshop_path(assigns(:workshop))
  end

  test 'should get edit' do
    @workshop = FactoryBot.create(:workshop)

    get :edit, params: { id: @workshop}
    assert_response :success
  end

  test 'should update workshop' do
    @workshop = FactoryBot.create(:workshop)
    attrs = FactoryBot.attributes_for(:workshop)

    put :update, params: { id: @workshop, workshop: attrs}
    assert_redirected_to admin_workshop_path(assigns(:workshop))
  end

  test 'should destroy workshop' do
    @workshop = FactoryBot.create(:workshop)

    assert_difference('Workshop.count', -1) do
      delete :destroy, params: { id: @workshop}
    end

    assert_redirected_to admin_workshops_path
  end
end
