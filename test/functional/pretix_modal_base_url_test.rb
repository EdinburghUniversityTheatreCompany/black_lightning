require "test_helper"

# The modal controller has no shop URL of its own: a home page that omits it would send
# every Buy Tickets click to "<slug>/".
class PretixModalBaseUrlTest < ActionController::TestCase
  tests StaticController

  test "the home page hands the modal controller the shop URL" do
    get :home

    assert_response :success
    assert_select "[data-controller=?][data-pretix-modal-base-url-value=?]",
                  "pretix-modal", PretixHelper::SHOP_URL
  end
end
