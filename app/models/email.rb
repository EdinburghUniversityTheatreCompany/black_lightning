class Email < ApplicationRecord
  belongs_to :attached_object, polymorphic: true, optional: false
  validates :email, presence: true

  # No duplicate emails on the same attached_object.
  validates_uniqueness_of :email, scope: :attached_object_id
end
