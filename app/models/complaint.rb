# == Schema Information
#
# Table name: complaints
# Database name: primary
#
#  id          :bigint           not null, primary key
#  comments    :text(16777215)
#  description :text(16777215)
#  resolved    :boolean
#  subject     :string(255)
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class Complaint < ApplicationRecord
  # Length validations enforcing database column limits
  validates :subject, length: { maximum: 255 }
  validates :description, length: { maximum: 16777215 }
  validates :comments, length: { maximum: 16777215 }
  has_paper_trail

  validates :subject, :description, presence: true

  before_destroy :stop_destroy

  normalizes :subject, with: ->(subject) { subject&.strip }

  # Everyone can create and it should not be possible to delete complaints.
  DISABLED_PERMISSIONS = %w[create destroy].freeze

  def html_class
    "error" unless resolved
  end

  def self.ransackable_attributes(auth_object = nil)
    # By default, there should be an accessible_by call on this, but just to be safe, I am also including it here.
    return unless auth_object.can?(:index, Complaint)

    %w[subject description comments]
  end

  def self.ransackable_associations(auth_object = nil)
    [ "versions" ]
  end

  private

  def stop_destroy
    self.errors.add(:base, "Complaints cannot be deleted")
    throw :abort
  end
end
