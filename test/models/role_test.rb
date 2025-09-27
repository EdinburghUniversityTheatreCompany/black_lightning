# == Schema Information
#
# Table name: roles
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

class RoleTest < ActionView::TestCase
  test "purge member" do
    role = roles(:member)

    count_pre_purge = role.users.count

    assert count_pre_purge > 0, "Members role does not have any users in the test. Attach some."
    assert_not role.purge

    assert_equal count_pre_purge, role.reload.users.count, "The amount of users changed in the purge, even though members should not be purged.."
  end

  test "purge other role" do
    role = roles(:committee)

    count_pre_purge = role.users.count

    assert count_pre_purge > 0, "Committee role does not have any users in the test. Attach some."
    assert role.purge

    assert_equal 0, role.reload.users.count, "There are still some users attached."
  end

  test "archive other role" do
    suffix = "TEST_ARCHIVE"
    role = roles(:committee)

    user_count_pre_archive = role.users.count
    permission_count_pre_archive = role.permissions.count

    assert user_count_pre_archive, "Committee role does not have any users in the test. Attach some."
    assert permission_count_pre_archive, "Committee role does not have any permissions in the test. Attach some."

    assert role.archive(suffix)

    assert_equal 0, role.reload.users.count, "There are still some users attached to the old role after archiving."
    assert_equal permission_count_pre_archive, role.reload.permissions.count, "Committee role lost permissions during archiving."

    # Check for the new role.
    new_role = Role.find_by(name: "#{role.name} #{suffix}")

    assert_equal user_count_pre_archive, new_role.users.count, "Not all users were transferred to the new role"
    assert_equal 0, new_role.permissions.count, "The new role obtained permissions"
  end

  test "Archive when archival role already exists should just add the users to the existing role" do
    suffix = "TEST_ARCHIVE"
    role = roles(:committee)

    users_on_role = role.users.to_a
    assert users_on_role.any?, "There are no users on the role to be archived. Add some."

    # Pre-create the archival role to see if archiving adds users to the archival role.
    archival_role = Role.create(name: "#{role.name} #{suffix}")

    # Add a user to the archival role
    user = users(:user)
    archival_role.users << user

    assert user.reload.has_role?(archival_role.name), "Adding the user to the archival role did not work"

    # Archive existing role.
    role.archive(suffix)

    assert role.reload.users.empty?, "There are still users on the original role after archiving."

    # Find the archival role and make sure it is the same, and that the old one has not been replaced.
    assert_equal archival_role, Role.find_by(name: "#{role.name} #{suffix}")

    # Test if users on role get moved to archival role.
    assert_includes archival_role.reload.users, users_on_role.first

    # Check if the original user on that role is also still there and is not overwritten.
    assert_includes archival_role.reload.users, user
  end

  test "archive with blank suffix" do
    role = roles(:committee)

    assert_not role.archive(""), "Archiving with a blank suffix should fail"
    assert_includes role.errors.full_messages, "Suffix cannot be blank when archiving a role"
  end

  test "Cannot change role name if it is hardcoded" do
    # Start with a hardcoded name.
    role = roles(:committee)

    role.name = "Nonsense Not Hardcode"
    assert_not role.valid?, "Hardcoded name validation did not fail for a hardcoded name"
    assert_includes role.errors.full_messages, "Name is hardcoded and cannot be altered"
  end

  test "Can change role name if not hardcoded" do
    role = Role.create(name: "Pineapple")

    role.name = "New Role Name"
    assert role.valid?, "Validation failed for a non-hardcoded name"
  end

  test "trained_role? returns true for roles with 'Trained' in name" do
    trained_role = Role.new(name: "DM Trained")
    assert trained_role.trained_role?, "trained_role? should return true for roles with 'Trained' in name"

    another_trained_role = Role.new(name: "Bar Trained")
    assert another_trained_role.trained_role?, "trained_role? should return true for roles with 'Trained' in name"

    mixed_case_role = Role.new(name: "First Aid Trained")
    assert mixed_case_role.trained_role?, "trained_role? should return true for roles with 'Trained' in name"
  end

  test "trained_role? returns false for roles without 'Trained' in name" do
    non_trained_role = Role.new(name: "Member")
    assert_not non_trained_role.trained_role?, "trained_role? should return false for roles without 'Trained' in name"

    committee_role = Role.new(name: "Committee")
    assert_not committee_role.trained_role?, "trained_role? should return false for roles without 'Trained' in name"

    admin_role = Role.new(name: "Admin")
    assert_not admin_role.trained_role?, "trained_role? should return false for roles without 'Trained' in name"
  end

  test "trained_role? returns false for nil name" do
    role_with_nil_name = Role.new(name: nil)
    assert_not role_with_nil_name.trained_role?, "trained_role? should return false for nil name"
  end

  test "remove_user removes user from role" do
    role = roles(:committee)
    user = FactoryBot.create(:user)

    # Add user to role first
    role.users << user
    assert_includes role.users, user, "User should be in role before removal"

    # Remove user from role
    role.remove_user(user)
    assert_not_includes role.reload.users, user, "User should be removed from role"
  end

  test "remove_user does nothing if user not in role" do
    role = roles(:committee)
    user = FactoryBot.create(:user)

    # Ensure user is not in role
    assert_not_includes role.users, user, "User should not be in role initially"

    initial_user_count = role.users.count

    # Try to remove user from role
    role.remove_user(user)

    assert_equal initial_user_count, role.reload.users.count, "User count should not change when removing user not in role"
  end

  test "cannot destroy hardcoded role" do
    role = roles(:admin)  # Admin is in HARDCODED_NAMES

    assert_not role.destroy, "Hardcoded role should not be destroyable"
    assert_includes role.errors.full_messages, "Cannot delete hardcoded role 'Admin' as it is referenced in code"
    assert role.persisted?, "Hardcoded role should still exist in database"
  end

  test "cannot destroy non-purgeable role" do
    role = roles(:member)  # member is in NON_PURGEABLE_ROLES

    assert_not role.destroy, "Non-purgeable role should not be destroyable"
    assert_includes role.errors.full_messages, "Cannot delete role 'Member' as it is protected from deletion"
    assert role.persisted?, "Non-purgeable role should still exist in database"
  end

  test "can destroy regular role" do
    role = FactoryBot.create(:role, name: "Test Role")

    assert role.destroy, "Regular role should be destroyable"
    assert_not Role.exists?(role.id), "Regular role should be removed from database"
  end

  test "cannot destroy committee role" do
    role = roles(:committee)  # Committee is in HARDCODED_NAMES

    assert_not role.destroy, "Committee role should not be destroyable"
    assert_includes role.errors.full_messages, "Cannot delete hardcoded role 'Committee' as it is referenced in code"
    assert role.persisted?, "Committee role should still exist in database"
  end
end
