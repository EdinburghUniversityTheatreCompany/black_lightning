require "test_helper"

class Admin::GroupsControllerTest < ActionController::TestCase
  include ERB::Util
  include AcademicYearHelper

  setup do
    @admin = users(:admin)
    sign_in @admin

    @group = groups(:member)
  end

  test "should get index" do
    get :index

    assert_response :success
    assert_not_nil assigns(:groups)

    assert_equal "Groups", assigns(:title)
  end

  test "should get members group as admin" do
    members = []
    (0..2).each do
      members << FactoryBot.create(:member)
    end

    user = FactoryBot.create(:user)
    get :show, params: { id: @group }
    assert_response :success

    members.each do |member|
      assert_match html_escape(member.name_or_email), response.body
    end

    assert_no_match html_escape(user.name_or_email), response.body

    assert_match "Please add members from the membership activation page", response.body
  end

  test "should get members group as committee" do
    sign_out @admin
    sign_in FactoryBot.create(:committee)

    get :show, params: { id: @group }
    assert_response :success

    assert_no_match "You are not allowed to add members", response.body, "Committee members can see a message about adding users to groups when they do not have permission to do so."
  end

  test "should get committee group" do
    @group = Group.find_by(name: "committee")

    get :show, params: { id: @group }
    assert_response :success

    assert_match "Add User to Group", response.body
  end

  test "member can view trained group show page" do
    sign_out @admin
    sign_in users(:member)

    trained_group = groups(:dm_trained)
    get :show, params: { id: trained_group }
    assert_response :success
  end

  test "member cannot view non-trained group show page" do
    sign_out @admin
    sign_in users(:member)

    get :show, params: { id: groups(:committee) }
    assert_response :forbidden
  end

  test "member can view index and only sees trained groups" do
    sign_out @admin
    sign_in users(:member)

    get :index
    assert_response :success

    assigns(:groups).each do |group|
      assert group.trained_group?, "Non-trained group '#{group.name}' should not be visible to members on the index"
    end
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create group" do
    assert_difference("Group.count") do
      post :create, params: { group: { name: "Hexagon" } }
    end

    assert Group.where(name: "Hexagon").one?

    assert_redirected_to admin_group_path(assigns(:group))
  end

  test "should not create invalid group" do
    assert_no_difference("Group.count") do
      post :create, params: { group: { name: nil } }
    end

    assert_response :unprocessable_entity
  end

  test "should get edit for hardcoded group" do
    get :edit, params: { id: groups(:admin) }
    assert_response :success

    # The group is admin, which is hardcoded.
    assert_match "You cannot change the name of this group", response.body
  end

  test "should update group" do
    group = FactoryBot.create(:group)

    put :update, params: { id: group, group: { name: "Viking" } }

    assert "Viking", assigns(:group).name
    assert_redirected_to admin_group_path(group)
  end

  test "should not update hardcoded group" do
    put :update, params: { id: groups(:admin), group: { name: "Viking" } }

    assert_response :unprocessable_entity

    assert_equal "Member", Group.find(@group.id).name
  end

  test "should not update invalid group" do
    put :update, params: { id: @group, group: { name: nil } }

    assert_response :unprocessable_entity
  end

  test "should destroy group" do
    # Create a test group that can be destroyed (not hardcoded or non-purgeable)
    test_group = FactoryBot.create(:group, name: "Test Destroyable group")

    assert_difference("Group.count", -1) do
      delete :destroy, params: { id: test_group }
    end

    assert_redirected_to admin_groups_path
  end

  test "should add user as admin" do
    user = FactoryBot.create(:user, first_name: "Finbar", last_name: "the Viking")

    post :add_user, params: { id: @group, add_user_details: { user_id: user.id } }

    assert user.member?

    assert_equal [ "Finbar the Viking has been added to the group of Member" ], flash[:success]
    assert_redirected_to admin_group_url(@group)
  end

  test "should not add user who already has the group" do
    user = FactoryBot.create(:member, first_name: "Dennis", last_name: "the Donkey")

    post :add_user, params: { id: @group, add_user_details: { user_id: user.id } }

    assert user.member?

    assert_equal [ "Dennis the Donkey already has the group of Member" ], flash[:success]
    assert_redirected_to admin_group_url(@group)
  end

  test "should not add user that does not exist" do
    post :add_user, params: { id: @group, add_user_details: { user_id: -1 } }

    assert_equal [ "This user does not exist." ], flash[:error]
    assert_redirected_to admin_group_url(@group)
  end

  test "should not add user as regular user" do
    sign_out @admin

    signed_in_user = users(:member)
    sign_in signed_in_user

    assert signed_in_user.cannot?(:add_user, @group), "The user should not have permission to add users to the group."

    user = FactoryBot.create(:user, first_name: "Finbar", last_name: "the Viking")

    post :add_user, params: { id: @group, add_user_details: { user_id: user.id } }

    assert_not user.member?, "The user was added to the group even though non-admins should not be able to do so."
  end

  test "purge should remove all users but keep the group" do
    group = groups(:committee)

    user = FactoryBot.create(:user)

    user.join_group(group)

    assert User.in_group(group).any?

    delete :purge, params: { id: group }

    assert_empty User.in_group(group)
    assert group.persisted?

    assert_redirected_to admin_group_url(group)

    assert_match "All users have been removed from the group", flash[:success].first
  end

  test "cannot purge members" do
    assert User.in_group(@group).any?

    delete :purge, params: { id: @group }

    assert User.in_group(@group).any?

    assert_redirected_to admin_group_url(@group)
    assert_match "Something went wrong removing all users from", flash[:error].first
  end

  test "should remove user from group as admin" do
    user = FactoryBot.create(:user, first_name: "Finbar", last_name: "the Viking")
    user.join_group(@group)

    assert user.in_group?(@group)

    delete :remove_user, params: { id: @group, user_id: user.id }

    assert_not user.reload.in_group?(@group)
    assert_equal [ "Finbar the Viking has been removed from the group of Member" ], flash[:success]
    assert_redirected_to admin_group_url(@group)
  end

  test "should remove user from group if has parent group" do
    sign_out @admin

    # Create a user with manage_trained_groups permission
    user_with_permission = users(:committee)
    sign_in user_with_permission

    assert user_with_permission.can?(:remove_user, Group), "User should be able to remove users from trained group"

    # Create a trained group and add a user to it
    trained_group = FactoryBot.create(:group, name: "Test Trained")
    trained_group.parents << groups(:committee)
    user_to_remove = FactoryBot.create(:user, first_name: "Test", last_name: "User")
    user_to_remove.join_group(trained_group.name)

    assert user_to_remove.in_group?(trained_group.name)

    delete :remove_user, params: { id: trained_group.id, user_id: user_to_remove.id }

    assert_not user_to_remove.reload.in_group?(trained_group.name)
    assert_equal [ "Test User has been removed from the group of Test Trained" ], flash[:success]
    assert_redirected_to admin_group_url(trained_group)
  end

  test "should not remove user from arbitrary group without admin permission" do
    sign_out @admin

    # Create a user with manage_trained_groups permission
    user_with_permission = FactoryBot.create(:user)
    group = FactoryBot.create(:group, name: "Test Manager")
    user_with_permission.join_group(group.name)
    sign_in user_with_permission

    # Try to remove from a non-trained group
    user_to_remove = FactoryBot.create(:user, first_name: "Test", last_name: "User")
    user_to_remove.join_group(@group.name)

    assert user_to_remove.in_group?(@group.name)

    delete :remove_user, params: { id: @group, user_id: user_to_remove.id }

    assert user_to_remove.reload.in_group?(@group.name)
    assert_response 403
  end

  test "should not remove user who does not exist" do
    delete :remove_user, params: { id: @group, user_id: -1 }

    assert_equal [ "This user does not exist." ], flash[:error]
    assert_redirected_to admin_group_url(@group)
  end

  test "should not remove user who is not in the group" do
    user = FactoryBot.create(:user, first_name: "Finbar", last_name: "the Viking")

    assert_not user.in_group?(@group.name)

    delete :remove_user, params: { id: @group, user_id: user.id }

    assert_equal [ "Finbar the Viking was not in the group of Member" ], flash[:warning]
    assert_redirected_to admin_group_url(@group)
  end

  test "should add user to group if has parent group" do
    sign_out @admin

    # Create a user with manage_trained_groups permission
    user_with_permission = users(:committee)

    sign_in user_with_permission

    assert user_with_permission.can?(:add_user, Group), "User should be able to add users to trained group"

    # Create a trained group and try to add a user to it
    trained_group = FactoryBot.create(:group, name: "Test Trained")
    trained_group.parents << groups(:committee)
    user_to_add = FactoryBot.create(:user, first_name: "Test", last_name: "User")

    assert_not user_to_add.in_group?(trained_group.name)

    post :add_user, params: { id: trained_group, add_user_details: { user_id: user_to_add.id } }

    assert user_to_add.reload.in_group?(trained_group.name), "group should have the user added to it."
    assert_equal [ "Test User has been added to the group of Test Trained" ], flash[:success]
    assert_redirected_to admin_group_url(trained_group)
  end

  test "archive" do
    user = FactoryBot.create(:user)

    user.join_group(@group.name)

    assert @group.users.any?

    put :archive, params: { id: @group }

    assert_empty @group.users, "There are still users attached to the old group."
    assert @group.persisted?

    new_group = Group.find_by(name: "#{@group.name} #{academic_year_shorthand}")
    assert new_group.present?
    assert_includes new_group.users, user, "The user did not get moved to the new group."

    assert_redirected_to admin_group_url(@group)

    assert_match "Archived all users with the group", flash[:success].first
  end

  test "should not destroy hardcoded group" do
    hardcoded_group = groups(:admin)

    assert_no_difference("Group.count") do
      delete :destroy, params: { id: hardcoded_group }
    end

    assert_includes flash[:error], "Cannot delete hardcoded group 'Admin' as it is referenced in code"
    assert_redirected_to admin_group_path(hardcoded_group)
    assert Group.exists?(hardcoded_group.id), "Hardcoded group should still exist"
  end

  test "should not destroy non-purgeable group" do
    member_group = groups(:member)

    assert_no_difference("Group.count") do
      delete :destroy, params: { id: member_group }
    end

    assert_includes flash[:error], "Cannot delete group 'Member' as it is protected from deletion"
    assert_redirected_to admin_group_path(member_group)
    assert Group.exists?(member_group.id), "Non-purgeable group should still exist"
  end

  test "should destroy regular group" do
    regular_group = FactoryBot.create(:group, name: "Test group")

    assert_difference("Group.count", -1) do
      delete :destroy, params: { id: regular_group }
    end

    assert_includes flash[:success], "The group 'Test group' was successfully deleted."
    assert_redirected_to admin_groups_path
    assert_not Group.exists?(regular_group.id), "Regular group should be removed"
  end

  test "should not destroy committee group" do
    committee_group = groups(:committee)

    assert_no_difference("Group.count") do
      delete :destroy, params: { id: committee_group }
    end

    assert_includes flash[:error], "Cannot delete hardcoded group 'Committee' as it is referenced in code"
    assert_redirected_to admin_group_path(committee_group)
    assert Group.exists?(committee_group.id), "Committee group should still exist"
  end
end
