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
class Admin::StaffingJob < ApplicationRecord
  validates :name, presence: true

  belongs_to :staffable, polymorphic: true
  belongs_to :user, optional: true
  has_one :staffing_debt, class_name: 'Admin::StaffingDebt', foreign_key: 'admin_staffing_job_id'

  after_save :associate_with_debt
  after_destroy :dissassociate_from_debt

  has_paper_trail limit: 6

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

  # Returns the staffing jobs that are not associated with any debt and count towards staffing.
  def self.unassociated_staffing_jobs_that_count_towards_debt
    staffing_jobs = all.joins('LEFT OUTER JOIN admin_staffing_debts ON admin_staffing_debts.admin_staffing_job_id = admin_staffing_jobs.id').where('admin_staffing_debts.admin_staffing_job_id IS null')
    ids = staffing_jobs.map { |job| job.counts_towards_debt? ? job.id : nil }

    return all.where(id: ids)
  end

  # Associates itself with the soonest upcoming Maintenance Debt
  def associate_with_debt(skip_check = false)
    relevant_keys = previous_changes.keys.excluding('created_at', 'updated_at')

    # If the only change is the ID of the staffing debt, skip reallocating the debts to prevent a loop.
    # This means that if you update just the staffing debt, you can slightly mess up the debts,
    # but I can't currently think of a better solution.
    return if relevant_keys == ['admin_staffing_job_id']

    # Necessary in some cases, such as when changing the user on the staffing_job and the debt is still nil in the local instance.
    reload

    # If the staffing job is associated with a template, the job does not count towards debt or has no user,
    # do not associate with a debt. Just make sure the debt is nil.
    if self.staffable.is_a?(Admin::StaffingTemplate) || !self.counts_towards_debt? || user.nil? 
      staffing_debt.update(admin_staffing_job: nil) if staffing_debt.present? 
    else
      # &. makes sure that a staffing_debt is present, and only one of the keys in the array has to have changed for the staffing_debt to be disassociated.
      staffing_debt&.update(admin_staffing_job: nil) if relevant_keys.any? { |key| %w[state user_id staffable_id name].include?(key) }

      user.reallocate_staffing_debts
    end
  end

  def dissassociate_from_debt
    # If the staffing_job is currently associated with a debt, break the association, and reallocate the staffing debts.
    if staffing_debt.present?
      staffing_debt.update(admin_staffing_job: nil)

      user.reallocate_staffing_debts if user.present?
    end
  end
end
