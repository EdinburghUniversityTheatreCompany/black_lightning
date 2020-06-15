require 'test_helper'

class Admin::SeasonsControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)
  end

  test 'should get index' do
    FactoryBot.create_list(:season, 5)

    get :index
    assert_response :success
    assert_not_nil assigns(:events)
  end

  test 'should get show' do
    @season = FactoryBot.create(:season, venue: venues(:one))

    get :show, params: { id: @season }
    assert_response :success
  end

  test 'should get new' do
    get :new
    assert_response :success
  end

  test 'should create season' do
    attrs = FactoryBot.attributes_for(:season)

    assert_difference('Season.count') do
      post :create, params: { season: attrs }
    end

    assert_redirected_to admin_season_path(assigns(:season))
  end

  test 'should not create invalid season' do
    attrs = FactoryBot.attributes_for(:season)
    attrs[:start_date] = nil

    assert_no_difference('Season.count') do
      post :create, params: { season: attrs }
    end

    assert_response :unprocessable_entity
  end

  test 'should get edit' do
    @season = FactoryBot.create(:season)

    get :edit, params: { id: @season }
    assert_response :success
  end

  test 'should update season' do
    @season = FactoryBot.create(:season)
    attrs = FactoryBot.attributes_for(:season)

    workshop = FactoryBot.create(:workshop)

    attrs[:event_ids] = [workshop.id]

    put :update, params: { id: @season, season: attrs }

    assert_includes assigns(:season).events, workshop
    assert_redirected_to admin_season_path(assigns(:season))
  end

  test 'should not update invalid season' do
    @season = FactoryBot.create(:season)
    attrs = FactoryBot.attributes_for(:season)
    attrs[:end_date] = nil

    put :update, params: { id: @season, season: attrs }
    assert_response :unprocessable_entity
  end

  test 'should destroy season' do
    @season = FactoryBot.create(:season, team_member_count: 0, picture_count: 0)

    assert_difference('Season.count', -1) do
      delete :destroy, params: { id: @season }
    end

    assert_redirected_to admin_seasons_path
  end
end
