require "test_helper"

class StaticControllerTest < ActionController::TestCase
  include ActionDispatch::Routing::UrlFor

  fixtures :opportunities

  test "should get home" do
    FactoryBot.create_list(:show, 10)

    get :home
    assert_response :success
  end

  test "home shows at most 5 active opportunities" do
    get :home

    home_opportunities = assigns(:home_opportunities)
    assert home_opportunities.all?(&:active?), "all assigned opportunities should be active"
    # 6 active fixtures exist, so a real limit is needed to get exactly 5
    assert_equal 5, home_opportunities.count
  end

  test "should get contact" do
    get :show, params: { page: "contact" }
    assert_response :success
  end

  test "should get 404 when navigating to nonexistent page" do
    get :show, params: { page: "pineapples_and_the_hexagon_a_memoir" }
    assert_response 404
  end

  test "should get privacy policy" do
    get :show, params: { page: "privacy_policy" }
    assert_response :success
  end
end
