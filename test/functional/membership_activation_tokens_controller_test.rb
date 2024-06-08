require 'test_helper'

# TIP: If you get a forbidden error in any of these, that is because get_user raised an error.

class MembershipActivationTokensControllerTest < ActionController::TestCase
  setup do
    user = users(:user)
    user.update(consented: nil)

    @token = MembershipActivationToken.create(user: user)
  end

  test 'get activate for new user' do
    # Should not be logged in.

    get :activate, params: { id: @token }

    assert_nil flash[:error]
    assert_response :success

    # I was not quite sure how to best test that the user form is present, so I'm just testing if the hint is present.
    assert_match 'If you already have an account, please log in instead of completing this form twice.', response.body
    assert_not assigns(:user).saved_changes?
  end

  test 'get activate for existing user' do
    user = FactoryBot.create(:user)
    @token.update_attribute(:user, user)

    sign_in user

    get :activate, params: { id: @token }

    assert_nil flash[:error]
    assert_response :success

    # I was not quite sure how to best test that the user form is present, so I'm just testing if the hint is absent.
    assert_no_match 'If you already have an account, please sign in instead of completing this form twice.', response.body
    assert assigns(:user).persisted?
  end

  test 'cannot get activate when logged in while the token does not have an user' do
    @token.update_attribute(:user, nil)

    sign_in FactoryBot.create(:member)

    get :activate, params: { id: @token }

    assert_response 403
    assert_equal ['This token belongs to a new user, but you are already logged in. You are not allowed to activate this account.'], flash[:error]
  end

  test 'cannot get activate when logged in as the wrong user' do
    @token.update_attribute(:user, FactoryBot.create(:user))

    sign_in FactoryBot.create(:user)

    get :activate, params: { id: @token }

    assert_response 403
    assert_equal ['This token belongs to a different user. You are not allowed to activate this account.'], flash[:error]
  end

  test 'cannot get activate when the user that the token belongs to is logged in as member' do
    member = FactoryBot.create(:member)
    sign_in member

    @token.update_attribute(:user, member)

    get :activate, params: { id: @token }

    assert_response 403
    assert_equal ['You have already activated your account.'], flash[:error]
  end

  test 'cannot submit when not logged in but the token belongs to an user' do
    @token.update_attribute(:user, FactoryBot.create(:user))

    get :activate, params: { id: @token }

    assert_response 403
    assert_equal ['This token belongs to an existing user, but you are not logged in. Please log in and try again.'], flash[:error]
  end

  test 'submit for new member without being signed in' do
    # No account, so no sign in

    user_attributes = FactoryBot.attributes_for(:user)

    assert_no_difference 'User.count' do
      # Test the welcome email is send. It also sends a 'password changed' email, which is why the count should be 2.
      assert_difference 'ActionMailer::Base.deliveries.count', 2 do
        perform_enqueued_jobs do
          patch :submit, params: { id: @token, user: user_attributes, consent: 'true' }
        end
      end

      assert_nil flash[:error]
      assert_redirected_to admin_url

      assert_not_nil assigns(:user)
      assert assigns(:user).has_role?('Member')
      assert assigns(:user).consented.present?
    end
  end

  test 'submit for existing user when signed in' do
    sign_in @token.user

    user_attributes = FactoryBot.attributes_for(:user)

    assert_no_difference 'User.count' do
      # Test the welcome email is send again. It also sends a 'password changed' email, which is why the count should be 2.
      assert_difference 'ActionMailer::Base.deliveries.count', 2 do
        perform_enqueued_jobs do
          patch :submit, params: { id: @token, user: user_attributes, consent: 'true' }
          
        end
      end

      assert_nil flash[:error]
      assert_redirected_to admin_url

      assert_not_nil assigns(:user)
      assert assigns(:user).has_role?('Member')
      assert assigns(:user).consented.present?
    end
  end

  test 'cannot submit without consent' do
    user_attributes = FactoryBot.attributes_for(:user)

    patch :submit, params: { id: @token, user: user_attributes }

    assert_equal ['You need to accept the Terms and Conditions before continuing.'], flash[:error]
    assert_response :unprocessable_entity

    assert_not_nil assigns(:user)
    assert_not assigns(:user).saved_changes?

    # The user form has to be present, even though a user is passed, but this user has not persisted yet.
    assert_match 'If you already have an account, please log in instead of completing this form twice.', response.body
  end

  test 'cannot submit with invalid user attributes' do
    user_attributes = FactoryBot.attributes_for(:user, email: nil, first_name: 'Pineapple')

    patch :submit, params: { id: @token, user: user_attributes, consent: 'true' }

    assert_nil flash[:error]
    assert_response :unprocessable_entity

    assert_not_nil assigns(:user)
    assert_not assigns(:user).saved_changes?
  end
end