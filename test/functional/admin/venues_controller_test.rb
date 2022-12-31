require 'test_helper'

class Admin::VenuesControllerTest < ActionController::TestCase
  setup do
    @venue = venues(:two)

    sign_in users(:admin)
  end

  test 'should get index' do
    get :index
    assert_response :success
    assert_not_nil assigns(:venues)
  end

  test 'should get map' do
    get :map
    assert_response :success

    # Assert venues with locations are included and venues without locations are not.
    assert_match 'Bedlam Theatre', response.body
    assert_match 'Pleasance Theatre', response.body
    assert_no_match 'Roxy Central', response.body
  end

  test 'should get new' do
    get :new
    assert_response :success
  end

  test 'should create venue' do
    assert_difference('Venue.count') do
      post :create, params: { venue: { description: @venue.description, location: @venue.location, name: @venue.name } }
    end

    assert_redirected_to admin_venue_path(assigns(:venue))
  end

  test 'should not create invalid venue' do
    assert_no_difference('Venue.count') do
      post :create, params: { venue: { description: @venue.description, location: @venue.location, name: nil } }
    end

    assert_response :unprocessable_entity
  end

  test 'should show venue' do
    get :show, params: { id: @venue}
    assert_response :success
  end

  test 'should show venue without location specified' do
    get :show, params: { id: venues(:roxy)}
    assert_response :success
  end

  test 'should get edit' do
    get :edit, params: { id: @venue}
    assert_response :success
  end

  test 'should update venue' do
    new_name = FactoryBot.generate(:random_string)

    put :update, params: { id: @venue, venue: { name: new_name } }

    assert_equal new_name, assigns(:venue).name

    assert_redirected_to admin_venue_path(assigns(:venue))
  end

  test 'should not update invalid venue' do
    put :update, params: { id: @venue, venue: { name: nil } }
    assert_response :unprocessable_entity
  end

  test 'should destroy venue' do
    assert_difference('Venue.count', -1) do
      delete :destroy, params: { id: @venue }
    end

    assert_redirected_to admin_venues_path
  end
end
