
# == Schema Information
#
# Table name: admin_staffing_templates
# Database name: primary
#
#  id         :integer          not null, primary key
#  name       :string(255)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class Admin::StaffingTemplate < ApplicationRecord
  # Length validations enforcing database column limits
  validates :name, length: { maximum: 255 }
  include ApplicationHelper

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  has_many :staffing_jobs, as: :staffable, class_name: "Admin::StaffingJob", dependent: :destroy

  accepts_nested_attributes_for :staffing_jobs, reject_if: :all_blank, allow_destroy: true

  normalizes :name, with: ->(name) { name&.strip }

  def as_json(options = {})
    defaults = { include: [ staffing_jobs: {} ] }

    options = merge_hash(defaults, options)

    super(options)
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[name]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[staffing_jobs]
  end
end
