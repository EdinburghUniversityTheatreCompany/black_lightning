# == Schema Information
#
# Table name: admin_staffing_templates
#
# *id*::         <tt>integer, not null, primary key</tt>
# *name*::       <tt>string(255)</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
#--
# == Schema Information End
#++

class Admin::StaffingTemplate < ApplicationRecord
  include ApplicationHelper

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  has_many :staffing_jobs, as: :staffable, class_name: 'Admin::StaffingJob', dependent: :destroy

  accepts_nested_attributes_for :staffing_jobs, reject_if: :all_blank, allow_destroy: true

  normalizes :name, with: -> (name) { name&.strip }

  def as_json(options = {})
    defaults = { include: [staffing_jobs: {}] }

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
