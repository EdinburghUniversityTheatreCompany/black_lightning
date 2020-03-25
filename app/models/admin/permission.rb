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

  ##
  # Creates, Adds an existing or Removes a Admin::Permission from a role for the
  # given subject_class and array of actions.
  #
  # For example, an empty actions array would mean that the role has no permissions
  # for the subject_class.
  ##
  def self.update_permission(role, subject_class, actions)
    existing_permissions = role.permissions.where(subject_class: subject_class)

    if existing_permissions
      existing_permissions.each do |perm|
        unless actions.include? perm.action
          # The role no longer has this permission. Get rid
          role.permissions.delete(perm)
        end
      end
    end

    actions.each do |action|
      if (!existing_permissions) || (!existing_permissions.find_by_action(action))
        # Try to add the role to the existing permission
        if permission = Admin::Permission.where(action: action, subject_class: subject_class).first
          permission.roles << role
        else
          permission = Admin::Permission.new
          permission.action = action[0]
          permission.subject_class = subject_class
          permission.roles << role
        end

        permission.save!
      end
    end

    role.save!
  end
end
