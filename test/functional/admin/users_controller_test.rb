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

  # The breadcrumb names the record the controller loaded, not the id segment of the URL.
  test "the edit breadcrumb names the user instead of their id" do
    get :edit, params: { id: @user }

    assert_response :success
    assert_select "nav[aria-label=Breadcrumb]" do |nav|
      assert_match(/Users/, nav.first.text, "collection segments still titleize")
      assert_match(/#{Regexp.escape(@user.name)}/, nav.first.text)
      assert_no_match(/ #{@user.id} /, nav.first.text)
    end
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

  # Typing the name was never checked, so the prompt asks a plain question.
  test "the delete button asks a plain question naming the user" do
    get :show, params: { id: @user }

    assert_select "form[data-turbo-confirm=?]",
                  "Delete #{@user.name(users(:admin))}? Content that belongs to them may break."
  end

  # The breadcrumb names the user, so the profile shows the id itself, to its owner as well.
  test "show displays the user's id" do
    get :show, params: { id: @user }

    assert_response :success
    assert_select "li", text: /\AID:\s*#{@user.id}\z/
  end

  test "a member viewing their own profile sees their id" do
    sign_out users(:admin)
    member = FactoryBot.create(:member)
    sign_in member

    get :show, params: { id: member }

    assert_response :success
    assert_select "li", text: /\AID:\s*#{member.id}\z/
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

  test "activation creates a member and sends the profile completion email" do
    assert_difference "ActionMailer::Base.deliveries.count" do
      perform_enqueued_jobs do
        assert_difference("User.count") do
          post :create_activation, params: { user: { email: "newbie@example.com", first_name: "New", last_name: "Member", is_member: "1" } }
        end
      end
    end

    assert_redirected_to activate_admin_users_path
    assert User.with_role(:member).exists?(email: "newbie@example.com")
  end

  test "activation re-renders the form for an invalid user" do
    assert_no_difference("User.count") do
      post :create_activation, params: { user: { email: "", first_name: "New", last_name: "Member" } }
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
    assert_predicate flash[:success], :present?
  end

  test "should not update password when same as current password" do
    original_encrypted_password = put_password("password123")

    assert_equal original_encrypted_password, @user.encrypted_password
    assert_equal "Updated Name", @user.first_name
    # permitted_params must not mutate the live params: a re-rendered form needs them.
    assert_equal "password123", @controller.params[:user][:password]
  end

  test "should update password when different from current password" do
    original_encrypted_password = put_password("newpassword456")

    assert_not_equal original_encrypted_password, @user.encrypted_password
    assert @user.valid_password?("newpassword456")
    assert_not @user.valid_password?("password123")
    assert_equal "Updated Name", @user.first_name
  end

  test "should not update password when blank password submitted" do
    original_encrypted_password = put_password("")

    assert_equal original_encrypted_password, @user.encrypted_password
    assert @user.valid_password?("password123")
    assert_equal "Updated Name", @user.first_name
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

    assert_not_includes_user user
  end

  test "get autocomplete list for all users" do
    members = FactoryBot.create_list :member, 2

    users = FactoryBot.create_list :user, 2

    get :autocomplete_list, params: { show_non_members: "1" }

    members.each { |member| assert_includes_user(member) }

    users.each { |user| assert_includes_user(user) }

    # Read the parsed flag: string-slicing the raw JSON always came back nil.
    assert_not response.parsed_body["pagination"]["more"]
  end

  test "get autocomplete list excludes user when exclude_id provided" do
    member1 = FactoryBot.create(:member)
    member2 = FactoryBot.create(:member)

    get :autocomplete_list, params: { exclude_id: member1.id }

    assert_includes_user member2
    assert_not_includes_user member1
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

  test "merge page keeps the target's avatar by default when both users have one" do
    source_user = FactoryBot.create(:member)
    [ @user, source_user ].each do |user|
      user.avatar.attach(io: File.open(Rails.root.join("test", "test.png")), filename: "test.png", content_type: "image/png")
    end

    get :merge, params: { id: @user, source_user_id: source_user.id }

    assert_select "input#keep_target_avatar[checked]"
    assert_select "input#hidden_avatar", false
  end

  test "the merge page asks for its preview by GET to itself" do
    get :merge, params: { id: @user }

    assert_select "form[method=get][action=?] select[name=source_user_id]", merge_admin_user_path(@user)
  end

  test "should absorb user with field preferences" do
    target_user = FactoryBot.create(:member, first_name: "John", last_name: "Target")
    source_user = FactoryBot.create(:member, first_name: "Jane", last_name: "Source")
    source_id = source_user.id
    target_email = target_user.email

    post :absorb, params: {
      id: target_user.id,
      source_user_id: source_user.id,
      field_choice: { name: "source", email: "target" }
    }

    assert_redirected_to admin_user_path(target_user)
    target_user.reload
    assert_equal "Jane", target_user.first_name
    assert_equal "Source", target_user.last_name
    assert_equal target_email, target_user.email
    assert_not User.exists?(source_id), "Source user should be deleted"
  end

  private

  # Gives @user the password "password123", PUTs an update submitting `password` (and a new first
  # name), reloads @user and returns the encrypted password from before the request.
  def put_password(password)
    @user.update!(password: "password123", password_confirmation: "password123")
    original_encrypted_password = @user.reload.encrypted_password

    put :update, params: {
      id: @user,
      user: { password: password, password_confirmation: password, first_name: "Updated Name" }
    }

    assert_redirected_to admin_user_path(@user)
    @user.reload
    original_encrypted_password
  end

  # Assert on the parsed JSON: Faker name collisions make body-substring checks flaky, and a name
  # with & or < is escaped in the JSON so it never matches literally.
  def autocomplete_results
    response.parsed_body["results"]
  end

  def assert_includes_user(user)
    assert_includes autocomplete_results, { "id" => user.id, "text" => user.name_or_default }
  end

  def assert_not_includes_user(user)
    assert_not_includes autocomplete_results.map { |result| result["id"] }, user.id
  end
end
