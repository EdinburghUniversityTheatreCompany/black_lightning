require 'test_helper'

class MembershipActivationTokenTest < ActionView::TestCase
  test 'generate token' do
    token = MembershipActivationToken.new

    assert_nil token.token

    # Should create a token on validation.
    token = MembershipActivationToken.create

    assert_not_nil token.token

    # Make sure the token does not change when saving.
    current_token = token.token

    token.save

    assert current_token, token.token
  end

  test 'to_param is token' do
    token = MembershipActivationToken.create
    assert_equal token.token, token.to_param, 'If this fails, it means to_param does not return token anymore. Fix that, or replace most, if not all, references to @membership_activation_token and @token with @<variable name>.token'
  end
end
