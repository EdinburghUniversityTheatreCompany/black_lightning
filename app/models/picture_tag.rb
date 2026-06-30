# == Schema Information
#
# Table name: picture_tags
# Database name: primary
#
#  id          :bigint           not null, primary key
#  description :text(16777215)
#  name        :string(255)
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class PictureTag < ApplicationRecord
  # Length validations enforcing database column limits
  validates :name, length: { maximum: 255 }
  validates :description, length: { maximum: 16777215 }
  validates :name, :description, presence: true
  validates :name, uniqueness: { case_sensitive: false }

  has_and_belongs_to_many :pictures, optional: true

  normalizes :name, with: ->(name) { name&.strip }

  def self.ransackable_attributes(auth_object = nil)
    %w[description name id ordering]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[pictures]
  end
end
