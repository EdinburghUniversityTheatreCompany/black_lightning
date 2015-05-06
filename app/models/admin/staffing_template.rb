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

class Admin::StaffingTemplate < ActiveRecord::Base
  has_many :staffing_jobs, as: :staffable, class_name: 'Admin::StaffingJob', dependent: :destroy

  accepts_nested_attributes_for :staffing_jobs, reject_if: :all_blank, allow_destroy: true

  validates :name, presence: true

  attr_accessible :name, :staffing_jobs, :staffing_jobs_attributes
end
