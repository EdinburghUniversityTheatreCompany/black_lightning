##
# Represents a permission.
#
# E.g. can :test, SomeModel
# would be represented with action = "test" and subject_class = "SomeModel".
#
# == Schema Information
#
# Table name: admin_permissions
# Database name: primary
#
#  id            :integer          not null, primary key
#  action        :string(255)
#  subject_class :string(255)
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
class Admin::Permission < ApplicationRecord
  has_and_belongs_to_many :roles

  DISABLED_PERMISSIONS = %w[update create delete].freeze
  EXCLUDED_ROLES = [ "Admin", "Proposal Checker" ].freeze

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
