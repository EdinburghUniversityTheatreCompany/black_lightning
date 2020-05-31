require 'test_helper'

class Admin::PermissionTest < ActiveSupport::TestCase
  setup do
    @role = FactoryBot.create(:role)
    @actions = %w[read edit delete]
    @subject_class = 'Admin::Permission'
  end

  test 'can create new permission' do
    assert_difference 'Admin::Permission.count', @actions.count do
      Admin::Permission.update_permission(@role, @subject_class, @actions)
    end

    @actions.each do |action|
      assert_includes Admin::Permission.find_by(action: action, subject_class: @subject_class).roles, @role, 'If the result is nil, it means it cannot find a permission with the specified action and subject class'
    end
  end

  test 'can update existing permission with actions' do
    Admin::Permission.update_permission(@role, @subject_class, @actions)

    # Please make sure this array has at least one action that is not in @actions and has at least one action removed from @actions
    new_actions = %w[read edit new_action]

    assert_difference 'Admin::Permission.count', new_actions.count - (@actions & new_actions).count do
      Admin::Permission.update_permission(@role, @subject_class, new_actions)
    end

    (@actions - new_actions).each do |action|
      assert_not_includes Admin::Permission.find_by(action: action, subject_class: @subject_class).roles, @role, 'The permission that is not in new_actions still exists'
    end

    (@actions & new_actions).each do |action|
      assert_includes Admin::Permission.find_by(action: action, subject_class: @subject_class).roles, @role, 'The permission that is in new_actions does not exist'
    end
  end

  test 'can update existing permission with role' do
    Admin::Permission.update_permission(@role, @subject_class, @actions)

    other_role = FactoryBot.create(:role)

    Admin::Permission.update_permission(other_role, @subject_class, @actions)

    @actions.each do |action|
      permission = Admin::Permission.find_by(action: action, subject_class: @subject_class)
      assert_includes permission.roles, @role, 'The result no longer contains the original role'
      assert_includes permission.roles, other_role, 'The result does not contain the new role'
    end
  end
end
