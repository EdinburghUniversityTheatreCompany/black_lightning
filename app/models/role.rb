##
# Represents the different role that a User may have. Permissions are asigned using the
# Admin::PermissionsController
#
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
class Role < ApplicationRecord
  # The roles that are referenced directly in the code.
  # Changing the name would break the website, so this list is used to prevent name changes for these roles.
  HARDCODED_NAMES = ['Admin', 'Committee', 'DM Trained', 'Business Manager', 'First Aid Trained', 'Bar Trained'].freeze
  NON_PURGEABLE_ROLES = ['member']

  validates :name, presence: true
  validate :name_not_hardcoded

  has_and_belongs_to_many :users, join_table: :users_roles
  has_and_belongs_to_many :permissions, class_name: 'Admin::Permission'

  belongs_to :resource, polymorphic: true, optional: true

  scopify

  def self.ransackable_attributes(auth_object = nil)
    %w[name]
  end

  # Removes all users from the role.
  def purge
    # You cannot purge certain roles.
    return false if NON_PURGEABLE_ROLES.include?(name.downcase.strip)

    return ActiveRecord::Base.transaction do
      self.users.clear
    end
  end

    # Moves all users on this role to a new role with the academic year shorthand as a suffix.
    # This new role has no permissions, and the existing role keeps all permissions.
    def archive(suffix)
      if suffix.blank?
        errors.add(:base, 'Suffix cannot be blank when archiving a role')
        return false
      end

      return ActiveRecord::Base.transaction do
        # Create or find the archival role and move all users over.
        new_role = Role.find_or_create_by(name: "#{name} #{suffix}")
        new_role.users << self.users

        # Then clear them from this role.
        self.users.clear
      end
    end

  def name_not_hardcoded
    errors.add(:name, 'is hardcoded and cannot be altered') if Role::HARDCODED_NAMES.include?(name_was) && name != name_was
  end
end
