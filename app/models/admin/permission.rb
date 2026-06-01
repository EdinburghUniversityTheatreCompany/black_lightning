##
# Represents a permission.
#
# E.g. can :test, SomeModel
# would be represented with action = "test" and subject_class = "SomeModel".
#
# == Schema Information
#
# Table name: admin_permissions
#
# *id*::            <tt>integer, not null, primary key</tt>
# *action*::        <tt>string(255)</tt>
# *subject_class*:: <tt>string(255)</tt>
# *created_at*::    <tt>datetime, not null</tt>
# *updated_at*::    <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
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
  def self.update_permission(role, subject_class, actions, all_role_permissions = nil)
    # Filter from preloaded set if provided, otherwise query per subject_class.
    existing_permissions = if all_role_permissions
      all_role_permissions.select { |p| p.subject_class == subject_class }
    else
      role.permissions.where(subject_class: subject_class).to_a
    end

    existing_permissions.each do |permission|
      unless actions.include?(permission.action)
        role.permissions.delete(permission)
      end
    end

    actions.each do |action|
      next if existing_permissions.any? { |p| p.action == action }

      permission = Admin::Permission.find_or_initialize_by(action: action, subject_class: subject_class)
      permission.roles << role unless permission.persisted? && permission.roles.include?(role)
      permission.save!
    end

    role.save!
  end
end
