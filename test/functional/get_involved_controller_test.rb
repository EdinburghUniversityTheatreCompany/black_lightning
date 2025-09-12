require "test_helper"

class GetInvolvedControllerTest < ActionController::TestCase
  include SubpageHelper

  test "should get opportunities" do
    assert_routing "get_involved/opportunities", controller: "get_involved", action: "opportunities"

    @editable_block = FactoryBot.create(:editable_block, url: "get_involved/opportunities")
    FactoryBot.create_list(:opportunity, 10)

    get :opportunities
    assert_response :success
    assert_not_nil assigns(:opportunities)
  end

  test "should get a page" do
    assert_routing "get_involved/acting", controller: "get_involved", action: "page", page: "acting"

    FactoryBot.create(:editable_block, name: "Acting", url: "get_involved/acting")

    # To test if it gets the correct subpages.
    FactoryBot.create(:editable_block, name: "Auditions", url: "get_involved/acting/auditions")

    get :page, params: { page: "acting" }

    assert_response :success
    assert_nil assigns(:opportunities)

    assert_equal "Acting", assigns(:editable_block).name
  end

  test "should get 404" do
    get :page, params: { page: "finbar_the_viking" }

    assert_response 404
  end
end
