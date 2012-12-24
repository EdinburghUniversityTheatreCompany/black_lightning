require 'test_helper'

class ShowsControllerTest < ActionController::TestCase
  setup do
    @show = events(:one)
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

end
