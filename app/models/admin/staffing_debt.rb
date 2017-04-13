class Admin::StaffingDebt < ActiveRecord::Base
  belongs_to :user
  belongs_to :show
  belongs_to :admin_staffing_job, :class_name => 'Admin::StaffingJob'

  attr_accessible :admin_staffing_job_id, :dueBy

  validates :dueBy, presence: true

  #possible statuses
  #1 = not signed up to any slots and not over deadline
  #2 = signed up not completed staffing but not over deadline
  #3 = completed staffing job
  #4 = causing debt i.e. not staffed and over deadline
  def status

    if !self.admin_staffing_job.present?
      if self.dueBy < Date.today
        return 4
      else
        return 1
      end
    else
      if self.admin_staffing_job.completed
        return 3
      elsif self.dueBy < Date.today
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

end
