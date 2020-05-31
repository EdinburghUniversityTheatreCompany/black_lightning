require 'test_helper'

class AdminControllerTest < ActionController::TestCase
  tests Admin::DashboardController

  test 'should redirect to log in if not logged in' do
    get 'index'
    assert_redirected_to new_user_session_url
  end

  test 'should deny access if the user does not have backend access' do
    sign_in FactoryBot.create(:user)
    get 'index'
    # Redirects to access denied
    assert_redirected_to access_denied_url
  end
end
