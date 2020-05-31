require 'test_helper'

class Admin::ReportsControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)
  end

  test 'get index' do
    get :index

    assert_response :success
  end

  test 'not get index without permission' do
    sign_in FactoryBot.create(:user)
    get :index

    assert_redirected_to access_denied_url
  end

  test 'put membership report' do
    put :members

    assert_redirected_to admin_reports_path
  end

  test 'put roles report' do
    put :roles

    assert_redirected_to admin_reports_path
  end

  test 'put newsletter subscribe report' do
    put :newsletter_subscribers

    assert_redirected_to admin_reports_path
  end

  test 'put staffing report' do
    put :staffing
  
    assert_redirected_to admin_reports_path
  end
end
