require "test_helper"

class Admin::RolesControllerTest < ActionController::TestCase
  include ERB::Util
  include AcademicYearHelper

  setup do
    @admin = users(:admin)
    sign_in @admin

    @role = roles(:member)
  end

  test "should get index" do
    get :index

    assert_response :success
    assert_not_nil assigns(:roles)

    assert_equal "Roles", assigns(:title)
  end

  test "should get members role as admin" do
    members = []
    (0..2).each do
      members << FactoryBot.create(:member)
    end

    user = FactoryBot.create(:user)
    get :show, params: { id: @role }
    assert_response :success

    members.each do |member|
      assert_match html_escape(member.name_or_email), response.body
    end

    assert_no_match html_escape(user.name_or_email), response.body

    assert_match "Please add members from the membership activation page", response.body
  end

  test "should get members role as committee" do
    sign_out @admin
    sign_in FactoryBot.create(:committee)

    get :show, params: { id: @role }
    assert_response :success

    assert_no_match "You are not allowed to add members", response.body, "Committee members can see a message about adding users to roles when they do not have permission to do so."
  end

  test "should get committee role" do
    @role = Role.find_by(name: "committee")

    get :show, params: { id: @role }
    assert_response :success

    assert_match "Add User to Role", response.body
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create role" do
    assert_difference("Role.count") do
      post :create, params: { role: { name: "Hexagon" } }
    end

    assert Role.where(name: "Hexagon").one?

    assert_redirected_to admin_role_path(assigns(:role))
  end

  test "should not create invalid role" do
    assert_no_difference("Role.count") do
      post :create, params: { role: { name: nil } }
    end

    assert_response :unprocessable_entity
  end

  test "should get edit for hardcoded role" do
    get :edit, params: { id: roles(:admin) }
    assert_response :success

    # The role is admin, which is hardcoded.
    assert_match "You cannot change the name of this role", response.body
  end

  test "should update role" do
    role = FactoryBot.create(:role)

    put :update, params: { id: role, role: { name: "Viking" } }

    assert "Viking", assigns(:role).name
    assert_redirected_to admin_role_path(role)
  end

  test "should not update hardcoded role" do
    put :update, params: { id: roles(:admin), role: { name: "Viking" } }

    assert_response :unprocessable_entity

    assert_equal "Member", Role.find(@role.id).name
  end

  test "should not update invalid role" do
    put :update, params: { id: @role, role: { name: nil } }

    assert_response :unprocessable_entity
  end

  test "should destroy role" do
    # Create a test role that can be destroyed (not hardcoded or non-purgeable)
    test_role = FactoryBot.create(:role, name: "Test Destroyable Role")

    assert_difference("Role.count", -1) do
      delete :destroy, params: { id: test_role }
    end

    assert_redirected_to admin_roles_path
  end

  test "should add user" do
    user = FactoryBot.create(:user, first_name: "Finbar", last_name: "the Viking")

    post :add_user, params: { id: @role, add_user_details: { user_id: user.id } }

    assert user.has_role?("Member")

    assert_equal [ "Finbar the Viking has been added to the role of Member" ], flash[:success]
    assert_redirected_to admin_role_url(@role)
  end

  test "should not add user who already has the role" do
    user = FactoryBot.create(:member, first_name: "Dennis", last_name: "the Donkey")

    post :add_user, params: { id: @role, add_user_details: { user_id: user.id } }

    assert user.has_role?("Member")

    assert_equal [ "Dennis the Donkey already has the role of Member" ], flash[:success]
    assert_redirected_to admin_role_url(@role)
  end

  test "should not add user that does not exist" do
    post :add_user, params: { id: @role, add_user_details: { user_id: -1 } }

    assert_equal [ "This user does not exist." ], flash[:error]
    assert_redirected_to admin_role_url(@role)
  end

  test "should not add user as committee" do
    sign_out @admin
    sign_in users(:committee)

    user = FactoryBot.create(:user, first_name: "Finbar", last_name: "the Viking")

    post :add_user, params: { id: @role, add_user_details: { user_id: user.id } }

    assert_not user.has_role?("Member"), "The user was added to the role even though non-admins should not be able to do so."

    assert_equal [ "You cannot add users to roles. Only admins can do this. Please contact the IT subcommittee." ], flash[:error]
    assert_redirected_to admin_role_url(@role)
  end

  test "purge should remove all users but keep the role" do
    role = roles(:committee)

    user = FactoryBot.create(:user)

    user.add_role(role.name)

    assert User.with_role(role.name).any?

    delete :purge, params: { id: role }

    assert User.with_role(role.name).empty?
    assert role.persisted?

    assert_redirected_to admin_role_url(role)

    assert_match "All users have been removed from the Role", flash[:success].first
  end

  test "cannot purge members" do
    assert User.with_role(@role.name).any?

    delete :purge, params: { id: @role }

    assert User.with_role(@role.name).any?

    assert_redirected_to admin_role_url(@role)
    assert_match "Something went wrong removing all users from", flash[:error].first
  end

  test "should remove user from role as admin" do
    user = FactoryBot.create(:user, first_name: "Finbar", last_name: "the Viking")
    user.add_role(@role.name)

    assert user.has_role?(@role.name)

    delete :remove_user, params: { id: @role, user_id: user.id }

    assert_not user.reload.has_role?(@role.name)
    assert_equal [ "Finbar the Viking has been removed from the role of Member" ], flash[:success]
    assert_redirected_to admin_role_url(@role)
  end

  test "should remove user from trained role with manage_trained_roles permission" do
    sign_out @admin

    # Create a user with manage_trained_roles permission
    user_with_permission = FactoryBot.create(:user)
    permission = Admin::Permission.find_or_create_by(action: "manage_trained_roles", subject_class: "Role")
    role = FactoryBot.create(:role, name: "Test Manager")
    role.permissions << permission
    user_with_permission.add_role(role.name)
    sign_in user_with_permission

    # Create a trained role and add a user to it
    trained_role = FactoryBot.create(:role, name: "Test Trained")
    user_to_remove = FactoryBot.create(:user, first_name: "Test", last_name: "User")
    user_to_remove.add_role(trained_role.name)

    assert user_to_remove.has_role?(trained_role.name)

    # Verify the permission check works
    assert user_with_permission.can?(:remove_user, trained_role), "User should be able to remove users from trained role"

    puts "Calling delete with URL: #{remove_user_admin_role_path(trained_role, user_to_remove.id)}"
    delete :remove_user, params: { id: trained_role.id, user_id: user_to_remove.id }

    # Debug: check what happened
    puts "Flash success: #{flash[:success]}"
    puts "Flash error: #{flash[:error]}"
    puts "User still has role: #{user_to_remove.reload.has_role?(trained_role.name)}"

    assert_not user_to_remove.reload.has_role?(trained_role.name)
    assert_equal [ "Test User has been removed from the role of Test Trained" ], flash[:success]
    assert_redirected_to admin_role_url(trained_role)
  end

  test "should not remove user from non-trained role without admin permission" do
    sign_out @admin

    # Create a user with manage_trained_roles permission
    user_with_permission = FactoryBot.create(:user)
    permission = Admin::Permission.find_or_create_by(action: "manage_trained_roles", subject_class: "Role")
    role = FactoryBot.create(:role, name: "Test Manager")
    role.permissions << permission
    user_with_permission.add_role(role.name)
    sign_in user_with_permission

    # Try to remove from a non-trained role
    user_to_remove = FactoryBot.create(:user, first_name: "Test", last_name: "User")
    user_to_remove.add_role(@role.name)

    assert user_to_remove.has_role?(@role.name)

    delete :remove_user, params: { id: @role, user_id: user_to_remove.id }

    assert user_to_remove.reload.has_role?(@role.name)
    assert_equal [ "You cannot remove users from roles. Only admins can do this. Please contact the IT subcommittee." ], flash[:error]
    assert_redirected_to admin_role_url(@role)
  end

  test "should not remove user who does not exist" do
    delete :remove_user, params: { id: @role, user_id: -1 }

    assert_equal [ "This user does not exist." ], flash[:error]
    assert_redirected_to admin_role_url(@role)
  end

  test "should not remove user who is not in the role" do
    user = FactoryBot.create(:user, first_name: "Finbar", last_name: "the Viking")

    assert_not user.has_role?(@role.name)

    delete :remove_user, params: { id: @role, user_id: user.id }

    assert_equal [ "Finbar the Viking was not in the role of Member" ], flash[:warning]
    assert_redirected_to admin_role_url(@role)
  end

  test "should add user to trained role with manage_trained_roles permission" do
    sign_out @admin

    # Create a user with manage_trained_roles permission
    user_with_permission = FactoryBot.create(:user)
    permission = Admin::Permission.find_or_create_by(action: "manage_trained_roles", subject_class: "Role")
    role = FactoryBot.create(:role, name: "Test Manager")
    role.permissions << permission
    user_with_permission.add_role(role.name)
    sign_in user_with_permission

    # Create a trained role and try to add a user to it
    trained_role = FactoryBot.create(:role, name: "Test Trained")
    user_to_add = FactoryBot.create(:user, first_name: "Test", last_name: "User")

    assert_not user_to_add.has_role?(trained_role.name)

    post :add_user, params: { id: trained_role, add_user_details: { user_id: user_to_add.id } }

    assert user_to_add.reload.has_role?(trained_role.name)
    assert_equal [ "Test User has been added to the role of Test Trained" ], flash[:success]
    assert_redirected_to admin_role_url(trained_role)
  end

  test "archive" do
    user = FactoryBot.create(:user)

    user.add_role(@role.name)

    assert @role.users.any?

    put :archive, params: { id: @role }

    assert @role.users.empty?, "There are still users attached to the old role."
    assert @role.persisted?

    new_role = Role.find_by(name: "#{@role.name} #{academic_year_shorthand}")
    assert new_role.present?
    assert new_role.users.include?(user), "The user did not get moved to the new role."

    assert_redirected_to admin_role_url(@role)

    assert_match "Archived all users with the Role", flash[:success].first
  end

  test "should not destroy hardcoded role" do
    hardcoded_role = roles(:admin)

    assert_no_difference("Role.count") do
      delete :destroy, params: { id: hardcoded_role }
    end

    assert_includes flash[:error], "Cannot delete hardcoded role 'Admin' as it is referenced in code"
    assert_redirected_to admin_role_path(hardcoded_role)
    assert Role.exists?(hardcoded_role.id), "Hardcoded role should still exist"
  end

  test "should not destroy non-purgeable role" do
    member_role = roles(:member)

    assert_no_difference("Role.count") do
      delete :destroy, params: { id: member_role }
    end

    assert_includes flash[:error], "Cannot delete role 'Member' as it is protected from deletion"
    assert_redirected_to admin_role_path(member_role)
    assert Role.exists?(member_role.id), "Non-purgeable role should still exist"
  end

  test "should destroy regular role" do
    regular_role = FactoryBot.create(:role, name: "Test Role")

    assert_difference("Role.count", -1) do
      delete :destroy, params: { id: regular_role }
    end

    assert_includes flash[:success], "The role 'Test Role' was successfully deleted."
    assert_redirected_to admin_roles_path
    assert_not Role.exists?(regular_role.id), "Regular role should be removed"
  end

  test "should not destroy committee role" do
    committee_role = roles(:committee)

    assert_no_difference("Role.count") do
      delete :destroy, params: { id: committee_role }
    end

    assert_includes flash[:error], "Cannot delete hardcoded role 'Committee' as it is referenced in code"
    assert_redirected_to admin_role_path(committee_role)
    assert Role.exists?(committee_role.id), "Committee role should still exist"
  end
end
