require 'test_helper'

class Devise::SessionsControllerTest < ActionController::TestCase
  test 'Signing in with @sms.ed.ac.uk for account with @ed.ac.uk works' do
    @request.env['devise.mapping'] = Devise.mappings[:user]

    password = '123Hel#2'

    FactoryBot.create(:user, email: 's1234567@ed.ac.uk', password:)

    post :create, params: { user: { 'email' => 's1234567@sms.ed.ac.uk', password: } }

    assert_redirected_to '/', 'If this does not redirect, it likely loaded the same page again with some error'
  end
end
