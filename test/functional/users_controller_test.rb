require 'test_helper'

class UsersControllerTest < ActionController::TestCase
  test 'should get show for public profile' do
    @user = FactoryBot.create(:user, public_profile: true)

    get :show, params: { id: @user }

    assert_response :success
    assert_equal @user.team_memberships(true), assigns(:team_memberships)
  end

  test 'should get access_denied for private profile' do
    @user = FactoryBot.create(:user, public_profile: false)

    get :show, params: { id: @user }

    assert_redirected_to access_denied_url
  end
end