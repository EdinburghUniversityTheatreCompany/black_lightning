require 'test_helper'

class Admin::WorkshopsControllerTest < ActionController::TestCase
  setup do
    sign_in FactoryGirl.create(:admin)
  end

  test "should get index" do
    FactoryGirl.create_list(:workshop, 10)

    get :index
    assert_response :success
    assert_not_nil assigns(:workshops)
  end

  test "should get show" do
    @workshop = FactoryGirl.create(:workshop)

    get :show, id: @workshop
    assert_response :success
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create workshop" do
    attrs = FactoryGirl.attributes_for(:workshop)

    assert_difference('Workshop.count') do
      post :create, workshop: attrs
    end

    assert_redirected_to admin_workshop_path(assigns(:workshop))
  end

  test "should get edit" do
    @workshop = FactoryGirl.create(:workshop)

    get :edit, id: @workshop
    assert_response :success
  end

  test "should update workshop" do
    @workshop = FactoryGirl.create(:workshop)
    attrs = FactoryGirl.attributes_for(:workshop)

    put :update, id: @workshop, workshop: attrs
    assert_redirected_to admin_workshop_path(assigns(:workshop))
  end

  test "should destroy workshop" do
    @workshop = FactoryGirl.create(:workshop)

    assert_difference('Workshop.count', -1) do
      delete :destroy, id: @workshop
    end

    assert_redirected_to admin_workshops_path
  end
end
