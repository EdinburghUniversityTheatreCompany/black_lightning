##
# Represents a job/position that may need to be staffed.
#
# == Schema Information
#
# Table name: admin_staffing_jobs
#
# *id*::             <tt>integer, not null, primary key</tt>
# *name*::           <tt>string(255)</tt>
# *staffable_id*::   <tt>integer</tt>
# *user_id*::        <tt>integer</tt>
# *created_at*::     <tt>datetime, not null</tt>
# *updated_at*::     <tt>datetime, not null</tt>
# *staffable_type*:: <tt>string(255)</tt>
#--
# == Schema Information End
#++
##
class Admin::StaffingJob < ApplicationRecord
  belongs_to :staffable, polymorphic: true
  belongs_to :user
  has_one :staffing_debt, :class_name => 'Admin::StaffingDebt', :foreign_key => 'admin_staffing_job_id'

  validates :name, presence: true

  ##
  # Get the start time in a js friendly fashion (UTC)
  ##
  def js_start_time
    return staffable.start_time.utc.to_i
  end

  ##
  # Get the end time in a js friendly fashion (UTC)
  ##
  def js_end_time
    return staffable.end_time.utc.to_i
  end

  def completed?
    return self.staffable.end_time < DateTime.now
  end
end
