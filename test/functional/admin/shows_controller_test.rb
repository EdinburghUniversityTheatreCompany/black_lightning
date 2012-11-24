require 'test_helper'

class Admin::ShowsControllerTest < ActionController::TestCase
  setup do
    @show = shows(:one)
    @user = User.find_by_email('admin@bedlamtheatre.co.uk')
    @user.add_role :admin
    sign_in @user

    @user = users(:one)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:shows)
  end

  test "should get show" do
    get :show, id: @show
    assert_response :success
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create show" do
    #Remove the existing entry:
    Show.find(@show).destroy

    assert_difference('Show.count') do
      post :create, show: { name: @show.name, slug: @show.slug, tagline: @show.tagline, description: @show.description }
    end

    assert_redirected_to admin_show_path(assigns(:show))
  end

  test "should get edit" do
    get :edit, id: @show
    assert_response :success
  end

  test "should update show" do
    put :update, id: @show, show: { name: @show.name, slug: @show.slug, tagline: @show.tagline, description: @show.description }
    assert_redirected_to admin_show_path(@show)
  end

  test "should destroy show" do
    assert_difference('Show.count', -1) do
      delete :destroy, id: @show
    end

    assert_redirected_to admin_shows_path
  end
end
