class Admin::MaintenanceDebt < ActiveRecord::Base
  belongs_to :user
  belongs_to :show

  attr_accessible :user,:user_id, :due_by, :show, :show_id, :status
  validates :due_by, presence: true

  enum state: [:unfulfilled, :converted, :completed]

  def self.searchfor(user_fname,user_sname,show_name,show_fulfilled)
    userIDs = User.where("first_name LIKE ? AND last_name LIKE ?","%#{user_fname}%","%#{user_sname}%").ids
    showIDs = Show.where("name LIKE ?","%#{show_name}%")
    maintenanceDebts = self.where(user_id: userIDs, show_id: showIDs)

    if !show_fulfilled
      maintenanceDebts = maintenanceDebts.unfulfilled
    end

    return maintenanceDebts
  end

  def convert_to_staffing_debt
    staffingDebt = Admin::StaffingDebt.new
    staffingDebt.due_by = self.due_by
    staffingDebt.show_id = self.show_id
    staffingDebt.user_id = self.user_id
    staffingDebt.converted = true
    staffingDebt.save!
    self.state = :converted
    self.save
  end

  def status(on_date = Date.today)
    case self.state
      when :converted then :converted
      when :completed then :completed
      else if self.due_by < on_date
             :causing_debt
           else
             :unfulfilled
           end
    end
  end


end
