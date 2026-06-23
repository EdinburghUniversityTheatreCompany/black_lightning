# == Schema Information
#
# Table name: emails
# Database name: primary
#
#  id                   :bigint           not null, primary key
#  attached_object_type :string(255)      not null
#  email                :string(255)
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  attached_object_id   :bigint           not null
#
# Indexes
#
#  index_emails_on_attached_object            (attached_object_type,attached_object_id)
#  index_emails_on_email_and_attached_object  (email,attached_object_id,attached_object_type) UNIQUE
#
class Email < ApplicationRecord
  belongs_to :attached_object, polymorphic: true, optional: false
  validates :email, presence: true

  # No duplicate emails on the same attached_object.
  validates_uniqueness_of :email, scope: [ :attached_object_type, :attached_object_id ]

  normalizes :email, with: ->(email) { email&.downcase.strip }
end
