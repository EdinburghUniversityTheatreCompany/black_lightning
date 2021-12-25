require 'test_helper'

class MembershipActivationTokensControllerTest < ActionController::TestCase
  setup do
    @token = MembershipActivationToken.create
  end

  test 'get activate for new user' do
    # Should not be signed in.

    get :activate, params: { id: @token }

    assert_response :success

    # I was not quite sure how to best test that the user form is present, so I'm just testing if the hint is present.
    assert_match 'If you already have an account, please sign in instead of completing this form twice.', response.body
    assert_not assigns(:user).persisted?
  end

  test 'get activate for existing user' do
    user = FactoryBot.create(:user)
    @token.update_attribute(:user, user)

    sign_in user

    get :activate, params: { id: @token }

    assert_response :success

    # I was not quite sure how to best test that the user form is present, so I'm just testing if the hint is absent.
    assert_no_match 'If you already have an account, please sign in instead of completing this form twice.', response.body
    assert assigns(:user).persisted?
  end

  test 'cannot get activate when signed in while the token does not have an user' do
    sign_in FactoryBot.create(:member)

    get :activate, params: { id: @token }

    assert_response 403
    assert_equal ['This token belongs to a new user, but you are already signed in.'], flash[:error]
  end

  test 'cannot get activate when signed in as the wrong user' do
    @token.update_attribute(:user, FactoryBot.create(:user))

    sign_in FactoryBot.create(:user)

    get :activate, params: { id: @token }

    assert_response 403
    assert_equal ['This token belongs to a different user.'], flash[:error]
  end

  test 'cannot get activate when the user thatthe token belongs to is signed in as member' do
    member = FactoryBot.create(:member)
    sign_in member

    @token.update_attribute(:user, member)

    get :activate, params: { id: @token }

    assert_response 403
    assert_equal ['You have already activated your account.'], flash[:error]
  end

  test 'cannot submit when not signed in but the token belongs to an user' do
    @token.update_attribute(:user, FactoryBot.create(:user))

    get :activate, params: { id: @token }

    assert_response 403
    assert_equal ['This token belongs to an existing user, but you are not signed in. Please sign in and try again.'], flash[:error]
  end

  test 'submit for new member' do
    # No account, so no sign in

    user_attributes = FactoryBot.attributes_for(:user)

    assert_difference 'User.count' do
      patch :submit, params: { id: @token, user: user_attributes, consent: 'true' }

      assert_not_nil assigns(:user)
      assert assigns(:user).has_role? :member
      assert assigns(:user).consented.present?
    end
  end

  test 'submit for existing user' do
    user = FactoryBot.create(:user)

    @token.update_attribute(:user, user)
    sign_in user

    user_attributes = FactoryBot.attributes_for(:user)

    assert_no_difference 'User.count' do
      patch :submit, params: { id: @token, user: user_attributes, consent: 'true' }

      assert_not_nil assigns(:user)
      assert assigns(:user).has_role? :member
      assert assigns(:user).consented.present?
    end
  end

  test 'cannot submit without consent' do
    user_attributes = FactoryBot.attributes_for(:user)

    patch :submit, params: { id: @token, user: user_attributes }

    assert_response :unprocessable_entity
    assert_match ['You need to give consent before you can create an account.'], flash[:error]

    assert_not_nil assigns(:user)
    assert_not assigns(:user).persisted?

    # The user form has to be present, even though a user is passed, but this user has not persisted yet.
    assert_match 'If you already have an account, please sign in instead of completing this form twice.', response.body
  end

  test 'cannot submit with invalid user attributes' do
    user_attributes = FactoryBot.attributes_for(:user, email: nil)

    patch :submit, params: { id: @token, user: user_attributes, consent: 'true' }

    assert_response :unprocessable_entity
    assert_nil flash[:error]

    assert_not_nil assigns(:user)
    assert_not assigns(:user).persisted?
  end
end