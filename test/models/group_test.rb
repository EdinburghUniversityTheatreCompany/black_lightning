# == Schema Information
#
# Table name: groups
#
# *id*::            <tt>integer, not null, primary key</tt>
# *name*::          <tt>string(255)</tt>
# *created_at*::    <tt>datetime, not null</tt>
# *updated_at*::    <tt>datetime, not null</tt>
# *resource_type*:: <tt>string(255)</tt>
# *resource_id*::   <tt>bigint</tt>
#--
# == Schema Information End
#++
require "test_helper"

class GroupTest < ActionView::TestCase
  test "purge member" do
    group = groups(:member)

    count_pre_purge = group.users.count

    assert count_pre_purge > 0, "Members group does not have any users in the test. Attach some."
    assert_not group.purge

    assert_equal count_pre_purge, group.reload.users.count, "The amount of users changed in the purge, even though members should not be purged.."
  end

  test "purge other group" do
    group = groups(:committee)

    count_pre_purge = group.users.count

    assert count_pre_purge > 0, "Committee group does not have any users in the test. Attach some."
    assert group.purge

    assert_equal 0, group.reload.users.count, "There are still some users attached."
  end

  test "archive other group" do
    suffix = "TEST_ARCHIVE"
    group = groups(:committee)

    user_count_pre_archive = group.users.count
    permission_count_pre_archive = group.permissions.count

    assert user_count_pre_archive, "Committee group does not have any users in the test. Attach some."
    assert permission_count_pre_archive, "Committee group does not have any permissions in the test. Attach some."

    assert group.archive(suffix)

    assert_equal 0, group.reload.users.count, "There are still some users attached to the old group after archiving."
    assert_equal permission_count_pre_archive, group.reload.permissions.count, "Committee group lost permissions during archiving."

    # Check for the new group.
    new_group = Group.find_by(name: "#{group.name} #{suffix}")

    assert_equal user_count_pre_archive, new_group.users.count, "Not all users were transferred to the new group"
    assert_equal 0, new_group.permissions.count, "The new group obtained permissions"
  end

  test "Archive when archival group already exists should just add the users to the existing group" do
    suffix = "TEST_ARCHIVE"
    group = groups(:committee)

    users_on_group = group.users.to_a
    assert users_on_group.any?, "There are no users on the group to be archived. Add some."

    # Pre-create the archival group to see if archiving adds users to the archival group.
    archival_group = Group.create(name: "#{group.name} #{suffix}")

    # Add a user to the archival group
    user = users(:user)
    archival_group.users << user

    assert user.reload.in_group?(archival_group.name), "Adding the user to the archival group did not work"

    # Archive existing group.
    group.archive(suffix)

    assert_empty group.reload.users, "There are still users on the original group after archiving."

    # Find the archival group and make sure it is the same, and that the old one has not been replaced.
    assert_equal archival_group, Group.find_by(name: "#{group.name} #{suffix}")

    # Test if users on group get moved to archival group.
    assert_includes archival_group.reload.users, users_on_group.first

    # Check if the original user on that group is also still there and is not overwritten.
    assert_includes archival_group.reload.users, user
  end

  test "archive with blank suffix" do
    group = groups(:committee)

    assert_not group.archive(""), "Archiving with a blank suffix should fail"
    assert_includes group.errors.full_messages, "Suffix cannot be blank when archiving a group"
  end

  test "Cannot change group name if it is hardcoded" do
    # Start with a hardcoded name.
    group = groups(:committee)

    group.name = "Nonsense Not Hardcode"
    assert_not group.valid?, "Hardcoded name validation did not fail for a hardcoded name"
    assert_includes group.errors.full_messages, "Name is hardcoded and cannot be altered"
  end

  test "Can change group name if not hardcoded" do
    group = Group.create(name: "Pineapple")

    group.name = "New Group Name"
    assert group.valid?, "Validation failed for a non-hardcoded name"
  end

  test "trained_group? returns true for groups with 'Trained' in name" do
    trained_group = Group.new(name: "DM Trained")
    assert trained_group.trained_group?, "trained_group? should return true for groups with 'Trained' in name"

    another_trained_group = Group.new(name: "Bar Trained")
    assert another_trained_group.trained_group?, "trained_group? should return true for groups with 'Trained' in name"

    mixed_case_group = Group.new(name: "First Aid Trained")
    assert mixed_case_group.trained_group?, "trained_group? should return true for groups with 'Trained' in name"
  end

  test "trained_group? returns false for groups without 'Trained' in name" do
    non_trained_group = Group.new(name: "Member")
    assert_not non_trained_group.trained_group?, "trained_group? should return false for groups without 'Trained' in name"

    committee_group = Group.new(name: "Committee")
    assert_not committee_group.trained_group?, "trained_group? should return false for groups without 'Trained' in name"

    admin_group = Group.new(name: "Admin")
    assert_not admin_group.trained_group?, "trained_group? should return false for groups without 'Trained' in name"
  end

  test "Opportunity Reviewer is in HARDCODED_NAMES" do
    assert_includes Group::HARDCODED_NAMES, "Opportunity Reviewer"
  end

  test "cannot change Opportunity Reviewer group name" do
    group = Group.find_or_create_by!(name: "Opportunity Reviewer")

    group.name = "Something Else"
    assert_not group.valid?, "Hardcoded name validation did not fail for Opportunity Reviewer"
    assert_includes group.errors.full_messages, "Name is hardcoded and cannot be altered"
  end

  test "Member is in HARDCODED_NAMES and cannot be renamed, whatever its casing" do
    assert Group.hardcoded_name?("Member")
    assert Group.hardcoded_name?("member"), "The production row may be stored lowercase; the guard must not depend on casing"

    group = groups(:member)
    group.name = "Subscriber"
    assert_not group.valid?, "Renaming the member group should be refused"
    assert_includes group.errors.full_messages, "Name is hardcoded and cannot be altered"

    group.reload.name = "MEMBER"
    assert group.valid?, "Recasing a hardcoded name is not a rename: every check reads it case-insensitively"
  end

  test "Life Member cannot be renamed: pretix reads it and would silently drop every discount" do
    assert Group.hardcoded_name?("life member")

    group = Group.create!(name: "life member")
    group.name = "Lifetime Member"
    assert_not group.valid?
    assert_includes group.errors.full_messages, "Name is hardcoded and cannot be altered"
  end

  test "hardcoding the member group does not stop it being archived" do
    suffix = "TEST_ARCHIVE"
    group = groups(:member)
    user_ids = group.users.ids
    assert user_ids.any?, "Member group does not have any users in the test. Attach some."

    assert group.archive(suffix), group.errors.full_messages.join(", ")

    assert_equal 0, group.reload.users.count, "Members were not moved off the member group"
    archived = Group.find_by(name: "Member #{suffix}")
    assert_not_nil archived, "The archival group was not created"
    assert_equal user_ids.sort, archived.users.ids.sort, "Not every member reached the archival group"
    assert_equal "Member", group.name, "Archiving must leave the hardcoded name untouched"
  end

  test "cannot destroy Opportunity Reviewer group" do
    group = Group.find_or_create_by!(name: "Opportunity Reviewer")

    assert_not group.destroy, "Opportunity Reviewer group should not be destroyable"
    assert_includes group.errors.full_messages, "Cannot delete hardcoded group 'Opportunity Reviewer' as it is referenced in code"
    assert group.persisted?, "Opportunity Reviewer group should still exist in database"
  end

  test "trained_group? returns false for nil name" do
    group_with_nil_name = Group.new(name: nil)
    assert_not group_with_nil_name.trained_group?, "trained_group? should return false for nil name"
  end

  test "remove_user removes user from group" do
    group = groups(:committee)
    user = FactoryBot.create(:user)

    # Add user to group first
    group.users << user
    assert_includes group.users, user, "User should be in group before removal"

    # Remove user from group
    group.remove_user(user)
    assert_not_includes group.reload.users, user, "User should be removed from group"
  end

  test "remove_user does nothing if user not in group" do
    group = groups(:committee)
    user = FactoryBot.create(:user)

    # Ensure user is not in group
    assert_not_includes group.users, user, "User should not be in group initially"

    initial_user_count = group.users.count

    # Try to remove user from group
    group.remove_user(user)

    assert_equal initial_user_count, group.reload.users.count, "User count should not change when removing user not in group"
  end

  test "cannot destroy hardcoded group" do
    group = groups(:admin)  # Admin is in HARDCODED_NAMES

    assert_not group.destroy, "Hardcoded group should not be destroyable"
    assert_includes group.errors.full_messages, "Cannot delete hardcoded group 'Admin' as it is referenced in code"
    assert group.persisted?, "Hardcoded group should still exist in database"
  end

  test "cannot destroy non-purgeable group" do
    group = groups(:member)  # member is in NON_PURGEABLE_NAMES

    assert_not group.destroy, "Non-purgeable group should not be destroyable"
    assert_includes group.errors.full_messages, "Cannot delete group 'Member' as it is protected from deletion"
    assert group.persisted?, "Non-purgeable group should still exist in database"
  end

  test "can destroy regular group" do
    group = FactoryBot.create(:group, name: "Test Group")

    assert group.destroy, "Regular group should be destroyable"
    assert_not Group.exists?(group.id), "Regular group should be removed from database"
  end

  test "cannot destroy committee group" do
    group = groups(:committee)  # Committee is in HARDCODED_NAMES

    assert_not group.destroy, "Committee group should not be destroyable"
    assert_includes group.errors.full_messages, "Cannot delete hardcoded group 'Committee' as it is referenced in code"
    assert group.persisted?, "Committee group should still exist in database"
  end
end
