##
# Represents a review for a Show.
#
# == Schema Information
#
# Table name: reviews
# Database name: primary
#
#  id           :integer          not null, primary key
#  body         :text(16777215)
#  organisation :string(255)
#  rating       :decimal(2, 1)
#  review_date  :date
#  reviewer     :string(255)
#  title        :string(255)
#  url          :string(255)
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  event_id     :integer
#
# Indexes
#
#  index_reviews_on_event_id  (event_id)
#
class Review < ApplicationRecord
  validates :body, :reviewer, :review_date, :title, presence: true
  validates :rating, numericality: { greater_than: 0, allow_blank: true }

  belongs_to :event

  normalizes :reviewer, :organisation, :title, with: ->(value) { value&.strip }

  def reviewer_with_organisation
    "#{reviewer}#{" for #{organisation}" if organisation.present?}"
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[body event_id organisation rating review_date reviewer title url]
  end
end
