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
    return if name.downcase.strip == 'Member'

    User.with_role(name).all.each do |user|
      user.remove_role(self)
    end
  end

  def name_not_hardcoded
    errors.add(:name, 'is hardcoded and cannot be altered') if Role::HARDCODED_NAMES.include?(name_was) && name != name_was
  end
end
