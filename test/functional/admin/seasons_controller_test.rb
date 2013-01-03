require 'test_helper'

class Admin::SeasonsControllerTest < ActionController::TestCase
  setup do
    sign_in FactoryGirl.create(:admin)
  end

  test "should get index" do
    FactoryGirl.create_list(:season, 5)

    get :index
    assert_response :success
  end

  test "should get show" do
    @season = FactoryGirl.create(:season)

    get :show, id: @season
    assert_response :success
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create season" do
    attrs = FactoryGirl.attributes_for(:season)

    assert_difference('Season.count') do
      post :create, season: attrs
    end

    assert_redirected_to admin_season_path(assigns(:season))
  end

  test "should get edit" do
    @season = FactoryGirl.create(:season)

    get :edit, id: @season
    assert_response :success
  end

  test "should update season" do
    @season = FactoryGirl.create(:season)
    attrs = FactoryGirl.attributes_for(:season)

    put :update, id: @season, season: attrs
    assert_redirected_to admin_season_path(assigns(:season))
  end

  test "should destroy season" do
    @season = FactoryGirl.create(:season)

    assert_difference('Season.count', -1) do
      delete :destroy, id: @season
    end

    assert_redirected_to admin_seasons_path
  end
end
