require 'test_helper'

class ApplicationControllerTest < ActionController::TestCase
  tests ShowsController
  # The Shows Controller is a pretty simple controller, so, we can use it as a base without the controller influencing much.

  test 'access denied' do
    show = FactoryBot.create(:show, is_public: false)
    get :show, params: { id: show.slug }
    assert_response 403
  end

  test 'set globals' do
    get :index

    assert_equal 'it@bedlamtheatre.co.uk', assigns(:support_email)
    assert_equal 'http://test.host', assigns(:base_url)
    assert_equal 'http://test.host/shows', assigns(:meta)['og:url']
    assert_equal [:description, 'og:url', 'og:image', 'og:title', 'viewport', 'og:description'], assigns(:meta).keys
  end

  test 'report 500' do
    skip "I don't know how to test this."
    assert_response 500
  end

  test 'mobile device' do
    skip "I don't know how to test this."
  end
end
