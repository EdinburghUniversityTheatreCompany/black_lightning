require 'test_helper'

class Devise::PasswordsControllerTest < ActionController::TestCase
  test 'resetting password for @sms.ed.ac.uk normalizes to @ed.ac.uk' do
    @request.env['devise.mapping'] = Devise.mappings[:user]

    user = FactoryBot.create(:user, email: 'cookiemonster@sms.ed.ac.uk')

    assert user.email.ends_with?('@ed.ac.uk'), 'The email domain was not normalized to @ed.ac.uk'

    post :create, params: { user: { 'email' => 'cookiemonster@sms.ed.ac.uk' } }

    assert_redirected_to '/users/sign_in', 'If this does not redirect, it likely loaded the same page again with some error'
  end
end
