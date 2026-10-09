require "test_helper"

class ProfileCompletionsControllerTest < ActionController::TestCase
  setup do
    @incomplete_user = FactoryBot.create(:user, profile_completed_at: nil)
    @complete_user = FactoryBot.create(:user, profile_completed_at: Time.current)
  end

  test "show with valid token for incomplete profile user" do
    token = @incomplete_user.profile_completion_token

    get :show, params: { token: token }

    assert_response :success
    assert_equal @incomplete_user, assigns(:user)
    assert_equal "Complete Your Profile", assigns(:title)
    # Image upload needs sign-in, which the link alone is not.
    assert_select "[data-markdown-editor-upload-url-value]", false
  end

  test "show with valid token when already signed in as same user" do
    sign_in @incomplete_user
    token = @incomplete_user.profile_completion_token

    get :show, params: { token: token }

    assert_response :success
    assert_equal @incomplete_user, assigns(:user)
  end

  test "show with invalid token" do
    get :show, params: { token: "invalid_token" }

    assert_response 404
    assert_match "Invalid or expired profile completion token", response.body
  end

  test "show with an expired token" do
    token = @incomplete_user.profile_completion_token

    travel 8.days do
      get :show, params: { token: token }
    end

    assert_response 404
  end

  test "show with a token that is not a string" do
    get :show, params: { token: [ "invalid_token" ] }

    assert_response 404
  end

  test "show with token belonging to different user than signed in user" do
    different_user = FactoryBot.create(:user, profile_completed_at: nil)
    sign_in different_user
    token = @incomplete_user.profile_completion_token

    get :show, params: { token: token }

    assert_response 403
    assert_match "This profile completion link belongs to a different user", response.body
  end

  test "show for logged in user with incomplete profile" do
    sign_in @incomplete_user

    get :show

    assert_response :success
    assert_equal @incomplete_user, assigns(:user)
    assert_select "[data-markdown-editor-upload-url-value]"
  end

  test "show for logged in user with complete profile" do
    sign_in @complete_user

    get :show

    assert_response 403
    assert_match "You have already completed your profile", response.body
  end

  test "show when not logged in and no token" do
    get :show

    assert_response 403
    assert_match "You need to be logged in or have a valid profile completion link", response.body
  end

  test "update with valid token and consent completes profile" do
    token = @incomplete_user.profile_completion_token
    user_params = { first_name: "Updated", last_name: "Name", password: "newpassword123" }

    assert_nil @incomplete_user.profile_completed_at

    assert_enqueued_emails 1 do
      patch :update, params: { token: token, user: user_params, consent: "true" }
    end

    assert_redirected_to admin_path
    assert_equal [ "Your profile has been completed successfully!" ], flash[:success]

    @incomplete_user.reload
    assert_equal "Updated", @incomplete_user.first_name
    assert_equal "Name", @incomplete_user.last_name
    assert @incomplete_user.profile_complete?
    assert @incomplete_user.consented.present?
    assert_equal @incomplete_user, @controller.current_user
  end

  test "update for logged in user with incomplete profile" do
    sign_in @incomplete_user
    user_params = { first_name: "Updated", last_name: "Name" }

    patch :update, params: { user: user_params, consent: "true" }

    assert_redirected_to admin_path

    @incomplete_user.reload
    assert @incomplete_user.profile_complete?
    assert_equal @incomplete_user, @controller.current_user
  end

  test "update without consent fails" do
    token = @incomplete_user.profile_completion_token
    user_params = { first_name: "Updated", last_name: "Name" }

    patch :update, params: { token: token, user: user_params }

    assert_response :unprocessable_entity
    assert_equal [ "You need to accept the Terms and Conditions before continuing." ], flash[:error]

    @incomplete_user.reload
    assert_nil @incomplete_user.profile_completed_at
  end

  test "update with invalid user attributes fails" do
    token = @incomplete_user.profile_completion_token
    user_params = { password: "ab" }

    patch :update, params: { token: token, user: user_params, consent: "true" }

    assert_response :unprocessable_entity

    @incomplete_user.reload
    assert_nil @incomplete_user.profile_completed_at
  end

  test "same token cannot be replayed after profile completion" do
    token = @incomplete_user.profile_completion_token
    user_params = { first_name: "Valid", last_name: "User", password: "validpassword123" }

    assert_enqueued_emails 1 do
      patch :update, params: { token: token, user: user_params, consent: "true" }
    end

    assert_redirected_to admin_path
    @incomplete_user.reload
    assert_equal "Valid", @incomplete_user.first_name
    assert @incomplete_user.profile_complete?

    sign_out @incomplete_user

    patch :update, params: { token: token, user: { first_name: "Hacker" }, consent: "true" }

    assert_response 404
  end
end
