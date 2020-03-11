# == Schema Information
#
# Table name: admin_staffing_debts
#
#  id                    :integer          not null, primary key
#  user_id               :integer
#  show_id               :integer
#  due_by                :date
#  admin_staffing_job_id :integer
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  converted             :boolean
#  forgiven              :boolean          default(FALSE)
#
class Admin::StaffingDebt < ActiveRecord::Base
  belongs_to :user
  belongs_to :show
  belongs_to :admin_staffing_job, class_name: 'Admin::StaffingJob'

  attr_accessible :due_by, :user, :user_id, :show, :show_id, :admin_staffing_job, :admin_staffing_job_id

  validates :due_by, presence: true
  validates :show_id, presence: true
  validates :user_id, presence: true
  
  before_create :associate_staffing_debt_with_existing_staffing_job

  # the status of a staffing debt is determined by whether or not it has a staffing job and if that job is in the past
  def status(on_date = Date.today)
    # note that :awaiting_staffing indicates the staffing slot has not been completed yet AND the debt deadline hasn't passed
    return :forgiven if forgiven
    if !admin_staffing_job.present?
      return :not_signed_up unless due_by < on_date
      :causing_debt
    elsif admin_staffing_job.completed?
      :completed_staffing
    elsif due_by < on_date
      :causing_debt
    else
      :awaiting_staffing
    end
  end

  # returns if the staffing debt has been completed or not
  def fulfilled
    if admin_staffing_job.present?
      admin_staffing_job.completed?
    else
      forgiven
    end
  end

  def self.search_for(user_fname, user_sname, show_name, show_fulfilled)
    user_ids = User.where('first_name LIKE ? AND last_name LIKE ?', "%#{user_fname}%", "%#{user_sname}%").ids
    show_ids = Show.where('name LIKE ?', "%#{show_name}%")
    staffing_debts = where(user_id: user_ids, show_id: show_ids)

    staffing_debts = staffing_debts.unfulfilled unless show_fulfilled

    return staffing_debts
  end

  # returns uncompleted staffing debts
  def self.unfulfilled
    fulfilled_ids = all.map { |debt| debt.fulfilled ? debt.id : nil }
    return where.not(id: fulfilled_ids)
  end

  def forgive
    self.forgiven = true
    save
  end

  private 
  def associate_staffing_debt_with_existing_staffing_job
    # Only associate when the record is new(that's why it's in the after_create) and the record does not already have a staffing job.
    return if admin_staffing_job.present?

    jobs = Admin::StaffingJob.where(user: user).joins("LEFT OUTER JOIN admin_staffing_debts ON admin_staffing_debts.admin_staffing_job_id = admin_staffing_jobs.id").where("admin_staffing_debts.admin_staffing_job_id IS null")
    self.admin_staffing_job = jobs.find {|job| job.counts_towards_debt?}
  end
end
