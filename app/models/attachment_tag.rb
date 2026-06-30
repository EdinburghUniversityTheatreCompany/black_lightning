# == Schema Information
#
# Table name: attachment_tags
# Database name: primary
#
#  id          :bigint           not null, primary key
#  description :text(16777215)
#  name        :string(255)
#  ordering    :bigint
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_attachment_tags_on_ordering  (ordering)
#
class AttachmentTag < ApplicationRecord
  # Length validations enforcing database column limits
  validates :name, length: { maximum: 255 }
  validates :description, length: { maximum: 16777215 }
  validates :name, :description, presence: true
  validates :name, uniqueness: { case_sensitive: false }

  has_and_belongs_to_many :attachments, optional: true

  normalizes :name, with: ->(name) { name&.strip }

  default_scope { order(:ordering) }

  def self.ransackable_attributes(auth_object = nil)
    %w[description name ordering id]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[attachments]
  end
end
