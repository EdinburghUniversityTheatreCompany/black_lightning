##
# Represents feedback for a Show.
#
# == Schema Information
#
# Table name: admin_feedbacks
# Database name: primary
#
#  id         :integer          not null, primary key
#  body       :text(16777215)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  show_id    :integer
#
# Indexes
#
#  index_admin_feedbacks_on_show_id  (show_id)
#
class Admin::Feedback < ApplicationRecord
  # Length validations enforcing database column limits
  validates :body, length: { maximum: 16777215 }
  validates :show_id, :body, presence: true
  belongs_to :show, class_name: "Show"

  def self.ransackable_attributes(auth_object = nil)
    %w[body show_id]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[show]
  end
end
