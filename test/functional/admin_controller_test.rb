require 'test_helper'

class AdminControllerTest < ActionController::TestCase
  tests Admin::DashboardController

  test 'should redirect to log in if not logged in' do
    get 'index'
    assert_redirected_to new_user_session_url
  end

  test 'should deny access if the user does not have backend access' do
    sign_in users(:user)
    get 'index'
    # Redirects to access denied
    assert_response 403
  end

  test 'should deny access if consented is nil' do
    user = users(:member)
    user.consented = nil
    user.save
  
    sign_in user

    get 'index'

    # Redirects to access denied
    assert_response 403
  end

  test 'should deny access if consented is more than a year ago' do
    user = users(:member)
    user.consented = Date.current.advance(days: -1, years: -1)
    user.save

    sign_in user

    get 'index'

    # Redirects to access denied
    assert_response 403
  end
end
