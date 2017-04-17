class Admin::StaffingDebt < ActiveRecord::Base
  belongs_to :user
  belongs_to :show
  belongs_to :admin_staffing_job, :class_name => 'Admin::StaffingJob'

  attr_accessible :admin_staffing_job_id, :due_by

  validates :due_by, presence: true

  #possible statuses
  #1 = not signed up to any slots and not over deadline
  #2 = signed up not completed staffing but not over deadline
  #3 = completed staffing job
  #4 = causing debt i.e. not staffed and over deadline
  def status

    if !self.admin_staffing_job.present?
      if self.due_by < Date.today
        return 4
      else
        return 1
      end
    else
      if self.admin_staffing_job.completed
        return 3
      elsif self.due_by < Date.today
        return 4
      else
        return 2
      end
    end
  end

  def status_class
    out = case self.status
            when 1 then "warning"
            when 2 then ""
            when 3 then "success"
            when 4 then "error"
          end
    return out
  end

  def fulfilled
    if self.admin_staffing_job.present?
      return self.admin_staffing_job.completed
    else
      return false
    end
  end

  def self.searchfor(user_fname,user_sname,show_name,show_fulfilled)
    userIDs = User.where("first_name LIKE '%#{user_fname}%' AND last_name LIKE '%#{user_sname}%'").ids
    showIDs = Show.where("name LIKE '%#{show_name}%'")
    staffingDebts = self.where(user_id: userIDs, show_id: showIDs)

    if !show_fulfilled
      staffingDebts = staffingDebts.filter_fulfilled
    end

    return staffingDebts
  end

  def self.filter_fulfilled
    fulfilledids = self.all.map{ |debt| debt.fulfilled ? debt.id : nil }
    return self.where.not(id: fulfilledids)
  end

end
