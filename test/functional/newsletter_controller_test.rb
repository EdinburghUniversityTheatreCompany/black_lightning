require 'test_helper'

class NewsletterControllerTest < ActionController::TestCase
  setup do
    request.env["HTTP_REFERER"] = "where_i_came_from"
  end

  test "should subscribe to newsletter" do
    post :subscribe, email: "test@test.com"

    assert_redirected_to "where_i_came_from"
  end
end
