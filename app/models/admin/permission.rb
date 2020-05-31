##
# Represents a permission.
#
# E.g. can :test, SomeModel
# would be represented with action = "test" and subject_class = "SomeModel".
#--
# TODO: Tidy up this model. Name and Description are no longer required.
#++
#
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
##
class Admin::Permission < ApplicationRecord
  has_and_belongs_to_many :roles

  # Distinguishing between update, create, and delete does not make sense for the permissions.
  # Users with :manage permission will be able to edit the permissions.
  DISABLED_PERMISSIONS = %w[update create delete].freeze

  ##
  # Creates, Adds an existing or Removes a Admin::Permission from a role for the
  # given subject_class and array of actions.
  #
  # For example, an empty actions array would mean that the role has no permissions
  # for the subject_class.
  #
  # The actions array has to contain strings.
  ##
  def self.update_permission(role, subject_class, actions)
    # Get all existing permissions for this subject_class and role.
    existing_permissions = role.permissions.where(subject_class: subject_class)

    # For all of those permissions, check if it still has those permissions with the updated actions.
    existing_permissions&.each do |permission|
      unless actions.include? permission.action
        # The role no longer has this permission.
        # Remove the role from the permission, but keep the permission.
        role.permissions.delete(permission)
      end
    end

    actions.each do |action|
      next if existing_permissions&.find_by_action(action)

      # Try to find if a permission with this action and subject_class already exists.
      permission = Admin::Permission.where(action: action, subject_class: subject_class).first

      # If it doesn't, create it.
      if permission.nil?
        permission = Admin::Permission.new
        permission.action = action
        permission.subject_class = subject_class
      end

      # Add the current role to the permission.
      permission.roles << role
      permission.save!
    end

    role.save!
  end
end
