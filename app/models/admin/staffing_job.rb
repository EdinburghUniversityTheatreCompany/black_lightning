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
class Admin::StaffingJob < ActiveRecord::Base
  belongs_to :staffable, polymorphic: true
  belongs_to :user
  has_one :staffing_debt, :class_name => 'Admin::StaffingDebt', :foreign_key => 'admin_staffing_job_id'

  validates :name, presence: true

  attr_accessible :name, :user, :user_id

  after_save :associate_staffing_job_with_oldest_outstanding_debt
  

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

  def associate_staffing_job_with_oldest_outstanding_debt
    # Only check for outstanding debt if the user has changed and the new user is not nil. 
    if (self.user_id_changed? && self.user_id != nil)
      debts = Admin::StaffingDebt.where(user_id: user_id).order(:due_by).limit(1)
      unless debts.empty?
        self.staffing_debt = debts.first
      end
      # This applies the change, and thus no longer marks the user as changed
      @changed_attributes.delete(:user)
    end
  end

end
