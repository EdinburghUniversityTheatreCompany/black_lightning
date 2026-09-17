# == Schema Information
#
# Table name: admin_permissions
#
# *id*::            <tt>integer, not null, primary key</tt>
# *name*::          <tt>string(255)</tt>
# *description*::   <tt>string(255)</tt>
# *action*::        <tt>string(255)</tt>
# *subject_class*:: <tt>string(255)</tt>
# *created_at*::    <tt>datetime, not null</tt>
# *updated_at*::    <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
require "test_helper"

class Admin::PermissionTest < ActiveSupport::TestCase
  setup do
    @group = FactoryBot.create(:group)
    @actions = %w[read edit delete]
    @subject_class = "Admin::Permission"
  end

  test "can create new permission" do
    assert_difference "Admin::Permission.count", @actions.count do
      Admin::Permission.update_permission(@group, @subject_class, @actions)
    end

    @actions.each do |action|
      assert_includes Admin::Permission.find_by(action: action, subject_class: @subject_class).groups, @group, "If the result is nil, it means it cannot find a permission with the specified action and subject class"
    end
  end

  test "can update existing permission with actions" do
    Admin::Permission.update_permission(@group, @subject_class, @actions)

    # Please make sure this array has at least one action that is not in @actions and has at least one action removed from @actions
    new_actions = %w[read edit new_action]

    assert_difference "Admin::Permission.count", new_actions.count - (@actions & new_actions).count do
      Admin::Permission.update_permission(@group, @subject_class, new_actions)
    end

    (@actions - new_actions).each do |action|
      assert_not_includes Admin::Permission.find_by(action: action, subject_class: @subject_class).groups, @group, "The permission that is not in new_actions still exists"
    end

    (@actions & new_actions).each do |action|
      assert_includes Admin::Permission.find_by(action: action, subject_class: @subject_class).groups, @group, "The permission that is in new_actions does not exist"
    end
  end

  test "can update existing permission with group" do
    Admin::Permission.update_permission(@group, @subject_class, @actions)

    other_group = FactoryBot.create(:group)

    Admin::Permission.update_permission(other_group, @subject_class, @actions)

    @actions.each do |action|
      permission = Admin::Permission.find_by(action: action, subject_class: @subject_class)
      assert_includes permission.groups, @group, "The result no longer contains the original group"
      assert_includes permission.groups, other_group, "The result does not contain the new group"
    end
  end
end
