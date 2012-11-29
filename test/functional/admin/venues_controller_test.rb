require 'test_helper'

class Admin::VenuesControllerTest < ActionController::TestCase
  setup do
    @venue = venues(:one)

    @user = User.find_by_email('admin@bedlamtheatre.co.uk')
    @user.add_role :admin
    sign_in @user
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:venues)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create venue" do
    assert_difference('Venue.count') do
      post :create, venue: { description: @venue.description, location: @venue.location, name: @venue.name }
    end

    assert_redirected_to admin_venue_path(assigns(:venue))
  end

  test "should show venue" do
    get :show, id: @venue
    assert_response :success
  end

  test "should get edit" do
    get :edit, id: @venue
    assert_response :success
  end

  test "should update venue" do
    put :update, id: @venue, venue: { description: @venue.description, location: @venue.location, name: @venue.name }
    assert_redirected_to admin_venue_path(assigns(:venue))
  end

  test "should destroy venue" do
    assert_difference('Venue.count', -1) do
      delete :destroy, id: @venue
    end

    assert_redirected_to admin_venues_path
  end
end
