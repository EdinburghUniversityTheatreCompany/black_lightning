class Admin::StaffingDebt < ActiveRecord::Base
  belongs_to :user
  belongs_to :show
  belongs_to :admin_staffing_job, :class_name => 'Admin::StaffingJob'

  attr_accessible :admin_staffing_job_id, :due_by

  validates :due_by, presence: true

  def status
#note that :awaiting_staffing indicates the staffing slot has not been completed yet AND the debt deadline hasn't passed
    if !self.admin_staffing_job.present?
      if self.due_by < Date.today
        return :causing_debt
      else
        return :not_signed_up
      end
    else
      if self.admin_staffing_job.completed
        return :completed_staffing
      elsif self.due_by < Date.today
        return :causing_debt
      else
        return :awaiting_staffing
      end
    end
  end


  def fulfilled
    if self.admin_staffing_job.present?
      return self.admin_staffing_job.completed
    else
      return false
    end
  end

  def self.search_for(user_fname,user_sname,show_name,show_fulfilled)
    userIDs = User.where("first_name LIKE '%#{user_fname}%' AND last_name LIKE '%#{user_sname}%'").ids
    showIDs = Show.where("name LIKE '%#{show_name}%'")
    staffingDebts = self.where(user_id: userIDs, show_id: showIDs)

    if !show_fulfilled
      staffingDebts = staffingDebts.unfulfilled
    end

    return staffingDebts
  end

  def self.unfulfilled
    fulfilledids = self.all.map{ |debt| debt.fulfilled ? debt.id : nil }
    return self.where.not(id: fulfilledids)
  end


end
