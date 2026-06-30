# == Schema Information
#
# Table name: event_tags
# Database name: primary
#
#  id                            :bigint           not null, primary key
#  description                   :text(16777215)
#  name                          :string(255)
#  ordering                      :bigint
#  recommended_maintenance_debts :integer
#  recommended_staffing_debts    :integer
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#
# Indexes
#
#  index_event_tags_on_ordering  (ordering)
#
class EventTag < ApplicationRecord
  # Length validations enforcing database column limits
  validates :name, length: { maximum: 255 }
  validates :description, length: { maximum: 16777215 }
  validates :name, :description, presence: true
  validates :name, uniqueness: { case_sensitive: false }
  validates :recommended_maintenance_debts, numericality: { greater_than_or_equal_to: 0, allow_nil: true }
  validates :recommended_staffing_debts, numericality: { greater_than_or_equal_to: 0, allow_nil: true }

  has_and_belongs_to_many :events, optional: true

  default_scope { order(:ordering) }

  normalizes :name, with: ->(name) { name&.strip }

  def self.ransackable_attributes(auth_object = nil)
    %w[description id name ordering]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[events]
  end
end
