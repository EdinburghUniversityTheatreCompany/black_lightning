require "test_helper"

class SeasonsControllerTest < ActionController::TestCase
  test "should get index" do
    FactoryBot.create_list(:season, 2)

    get :index
    assert_response :success
    assert_not_nil assigns(:seasons)
  end

  test "should get show" do
    @season = FactoryBot.create(:season, show_count: 3, is_public: true)

    get :show, params: { id: @season.slug }
    assert_response :success
  end

  test "existing season constraint without any seasons" do
    assert_routing "pineapple", controller: "static", action: "show", page: "pineapple"
  end

  test "existing season constraint" do
    season = FactoryBot.create(:season)
    _other_seasons = FactoryBot.create_list(:season, 2)

    assert_recognizes({ controller: "seasons", action: "show", id: season.slug }, "//#{season.slug}")

    assert_routing "pineapple", controller: "static", action: "show", page: "pineapple"
  end
end
