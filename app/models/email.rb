# == Schema Information
#
# Table name: emails
#
# *id*::                   <tt>bigint, not null, primary key</tt>
# *email*::                <tt>string(255)</tt>
# *attached_object_type*:: <tt>string(255), not null</tt>
# *attached_object_id*::   <tt>bigint, not null</tt>
# *created_at*::           <tt>datetime, not null</tt>
# *updated_at*::           <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
class Email < ApplicationRecord
  belongs_to :attached_object, polymorphic: true, optional: false
  validates :email, presence: true

  # No duplicate emails on the same attached_object.
  validates_uniqueness_of :email, scope: [ :attached_object_type, :attached_object_id ]

  normalizes :email, with: ->(email) { email&.downcase.strip }
end
