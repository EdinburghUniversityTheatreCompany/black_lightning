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
  validates :name, presence: true

  belongs_to :staffable, polymorphic: true
  belongs_to :user, optional: true
  has_one :staffing_debt, class_name: 'Admin::StaffingDebt', foreign_key: 'admin_staffing_job_id'

  before_save :check_if_the_user_has_changed
  after_save :associate_staffing_job_with_oldest_outstanding_debt

  # The functions that use staffable don't check if it's a staffing instead of a template.
  # They should just hard-fail when the staffable is a template. That situation should simply not occur.

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
    return staffable.end_time < DateTime.now
  end

  def counts_towards_debt?
    return staffable.present? && staffable.counts_towards_debt? && name != 'Committee Rep'
  end

  def self.unassociated_staffing_jobs_that_count_towards_debt
    # Returns the staffing jobs that are not associated with any debt and count towards staffing.

    staffing_jobs = all.joins('LEFT OUTER JOIN admin_staffing_debts ON admin_staffing_debts.admin_staffing_job_id = admin_staffing_jobs.id').where('admin_staffing_debts.admin_staffing_job_id IS null')
    ids = staffing_jobs.map { |job| job.counts_towards_debt? ? job.id : nil }

    return all.where(id: ids)
  end

  private

  def check_if_the_user_has_changed
    @user_changed = user_id_changed?
  end

  def associate_staffing_job_with_oldest_outstanding_debt
    # If the staffing job is associated with a template, do not try to associate the staffing_job with a debt.
    # Check if the staffing job counts towards staffing and return if it does not.
    return if (self.staffable.is_a?(Admin::StaffingTemplate) || !self.counts_towards_debt?)

    # If the new user is nil, there can be no associated staffing_debt, so set it to nil.
    # Setting the user to nil does not always set user_id_changed to true, so this check takes place here.
    if !self.user.present?
      self.staffing_debt = nil
      return
    # Only check for outstanding debt if the user has changed.
    elsif @user_changed
      debts = Admin::StaffingDebt.where(user_id: user_id, admin_staffing_job: nil).unfulfilled.reorder(:due_by)
      if debts.empty?
        # If the user changed and there are no debts found, it should not stay associated with the old debt.
        self.staffing_debt = nil
      else
        self.staffing_debt = debts.first
      end
    end
  end
end
