require "test_helper"

class Admin::UsersControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)

    @user = FactoryBot.create(:user)
  end

  test "should get index" do
    get :index
    assert_response :success
  end

  test "should get index with non_members" do
    get :index, params: { show_non_members: 1 }

    assert_response :success
  end

  test "should get show" do
    get :show, params: { id: @user }
    assert_response :success
    assert assigns(:link_to_admin_events)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create user" do
    attributes = FactoryBot.attributes_for(:user)

    # Test the welcome email is send.
    assert_difference "ActionMailer::Base.deliveries.count" do
      perform_enqueued_jobs do
        assert_difference("User.count") do
          post :create, params: { user: attributes }
        end
      end
    end

    assert_redirected_to admin_user_path(assigns(:user))
  end

  test "should not create invalid user" do
    attributes = FactoryBot.attributes_for(:user, email: "")

    assert_no_difference("User.count") do
      post :create, params: { user: attributes }
    end

    assert_response :unprocessable_entity
  end

  test "should get edit" do
    get :edit, params: { id: @user }
    assert_response :success
  end

  test "role checkboxes should not be visible for non-admin users" do
    non_admin_user = users(:committee)
    sign_in(non_admin_user)

    get :edit, params: { id: @user }
    assert_response :success

    assert_no_match 'name="user[role_ids][]"', response.body
  end

  test "role checkboxes should be visible for admin users" do
    admin_user = users(:admin)
    sign_in(admin_user)

    get :edit, params: { id: @user }
    assert_response :success

    assert_match 'name="user[role_ids][]"', response.body
  end

  test "should update user" do
    role = Role.all.first
    attributes = FactoryBot.attributes_for(:user, role_ids: [ role.id ])

    # Explicitly test roles as they are only added to permitted_parms for admins.
    assert_not @user.has_role?(role), "User should not have the role yet before the test."

    put :update, params: { id: @user, user: attributes }

    assert_redirected_to admin_user_path(@user)
    assert @user.has_role?(role), "Role was not assigned to the test"
  end

  # Only admins should be able to update roles, so make sure that committee (who do have edit permission) cannot.
  test "committee cannot update roles on user" do
    sign_out users(:admin)
    sign_in users(:committee)

    role = Role.all.first
    attributes = FactoryBot.attributes_for(:user, role_ids: [ role.id ])

    # Explicitly test roles as they are only added to permitted_parms for admins.
    assert_not @user.has_role?(role), "User should not have the role yet before the test."

    put :update, params: { id: @user, user: attributes }

    assert_not @user.has_role?(role), "Role was assigned by a committee member when they should not be able to do that."
    assert_redirected_to admin_user_path(@user)
  end

  test "should not update invalid user" do
    attributes = FactoryBot.attributes_for(:user, phone_number: "This is not a phone number! This is a sentence!")

    put :update, params: { id: @user, user: attributes }

    assert_response :unprocessable_entity
  end

  test "should destroy user" do
    assert_difference("User.count", -1) do
      delete :destroy, params: { id: @user }
    end

    assert_redirected_to admin_users_path
  end

  test "should reset password" do
    post :reset_password, params: { id: @user }

    assert_redirected_to admin_user_url(@user)
  end

  test "should not update password when same as current password" do
    current_password = "password123"
    @user.update!(password: current_password, password_confirmation: current_password)
    @user.reload
    original_encrypted_password = @user.encrypted_password

    # Submit the same password that's currently set
    put :update, params: {
      id: @user,
      user: {
        password: current_password,
        password_confirmation: current_password,
        first_name: "Updated Name"
      }
    }

    assert_redirected_to admin_user_path(@user)
    @user.reload

    # Password should not have changed
    assert_equal original_encrypted_password, @user.encrypted_password, "Password should not have been updated when same as current"

    # But other fields should have been updated
    assert_equal "Updated Name", @user.first_name, "Other fields should still be updated"
  end

  test "should update password when different from current password" do
    current_password = "password123"
    new_password = "newpassword456"
    @user.update!(password: current_password, password_confirmation: current_password)
    @user.reload
    original_encrypted_password = @user.encrypted_password

    # Submit a different password
    put :update, params: {
      id: @user,
      user: {
        password: new_password,
        password_confirmation: new_password,
        first_name: "Updated Name"
      }
    }

    assert_redirected_to admin_user_path(@user)
    @user.reload

    # Password should have changed
    assert_not_equal original_encrypted_password, @user.encrypted_password, "Password should have been updated when different from current"

    # Verify user can log in with new password
    assert @user.valid_password?(new_password), "User should be able to authenticate with new password"
    assert_not @user.valid_password?(current_password), "User should not be able to authenticate with old password"

    # Other fields should have been updated too
    assert_equal "Updated Name", @user.first_name, "Other fields should still be updated"
  end

  test "should not update password when blank password submitted" do
    current_password = "password123"
    @user.update!(password: current_password, password_confirmation: current_password)
    @user.reload
    original_encrypted_password = @user.encrypted_password

    # Submit blank password
    put :update, params: {
      id: @user,
      user: {
        password: "",
        password_confirmation: "",
        first_name: "Updated Name"
      }
    }

    assert_redirected_to admin_user_path(@user)
    @user.reload

    # Password should not have changed
    assert_equal original_encrypted_password, @user.encrypted_password, "Password should not have been updated when blank"

    # User should still be able to log in with current password
    assert @user.valid_password?(current_password), "User should still be able to authenticate with current password"

    # Other fields should have been updated
    assert_equal "Updated Name", @user.first_name, "Other fields should still be updated"
  end

  test "get autocomplete list does not work when not signed in" do
    sign_out users(:admin)

    get :autocomplete_list

    assert_redirected_to new_user_session_path
  end

  test "get autocomplete list as member" do
    sign_out users(:admin)
    sign_in users(:member)

    members = FactoryBot.create_list :member, 5
    user = FactoryBot.create :user

    get :autocomplete_list

    members.each { |member| assert_includes_user(member) }

    assert_not_includes response.body, user.first_name, "Ocassionally fails if the first name is not unique"
    assert_not_includes response.body, user.last_name, "Ocassionally fails if the last name is not unique"
    assert_not_includes response.body, user.id.to_s
  end

  test "get autocomplete list for all users" do
    members = FactoryBot.create_list :member, 2

    users = FactoryBot.create_list :user, 2

    get :autocomplete_list, params: { show_non_members: "1" }

    members.each { |member| assert_includes_user(member) }

    users.each { |user| assert_includes_user(user) }

    assert_not response.body["pagination"]["more"]
  end

  test "get autocomplete list excludes user when exclude_id provided" do
    member1 = FactoryBot.create(:member)
    member2 = FactoryBot.create(:member)

    get :autocomplete_list, params: { exclude_id: member1.id }

    assert_includes response.body, member2.first_name
    assert_not_includes response.body, member1.id.to_s
  end

  # Merge flow tests

  test "should get merge page" do
    get :merge, params: { id: @user }
    assert_response :success
  end

  test "should get merge page with pre-selected source user" do
    source_user = FactoryBot.create(:member)

    get :merge, params: { id: @user, source_user_id: source_user.id }

    assert_response :success
    assert_equal source_user, assigns(:source_user)
  end

  test "should post merge_preview redirects to merge with source_user_id" do
    sign_in users(:admin)
    target_user = FactoryBot.create(:member)
    source_user = FactoryBot.create(:member)

    post :merge_preview, params: { id: target_user.id, source_user_id: source_user.id }

    assert_redirected_to merge_admin_user_path(target_user, source_user_id: source_user.id)
  end

  test "should absorb user with field preferences" do
    sign_in users(:admin)
    target_user = FactoryBot.create(:member, first_name: "John", last_name: "Target")
    source_user = FactoryBot.create(:member, first_name: "Jane", last_name: "Source")
    source_id = source_user.id

    post :absorb, params: {
      id: target_user.id,
      source_user_id: source_user.id,
      keep_from_source: [ "name" ]
    }

    assert_redirected_to admin_user_path(target_user)
    target_user.reload
    assert_equal "Jane", target_user.first_name
    assert_equal "Source", target_user.last_name
    assert_not User.exists?(source_id), "Source user should be deleted"
  end

  test "should absorb user without field preferences uses defaults" do
    sign_in users(:admin)
    target_user = FactoryBot.create(:member, first_name: "John", last_name: "Target")
    source_user = FactoryBot.create(:member, first_name: "Jane", last_name: "Source")
    source_id = source_user.id

    post :absorb, params: {
      id: target_user.id,
      source_user_id: source_user.id
    }

    assert_redirected_to admin_user_path(target_user)
    target_user.reload
    assert_equal "John", target_user.first_name  # Kept target values
    assert_equal "Target", target_user.last_name
    assert_not User.exists?(source_id), "Source user should be deleted"
  end

  private

  def assert_includes_user(user)
    assert_includes response.body, user.first_name
    assert_includes response.body, user.last_name
    assert_includes response.body, user.id.to_s
  end
end
