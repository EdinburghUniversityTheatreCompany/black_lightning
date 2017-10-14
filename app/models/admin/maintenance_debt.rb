class Admin::MaintenanceDebt < ActiveRecord::Base

  belongs_to :user
  belongs_to :show

  attr_accessible :user, :due_by, :show, :user_id, :show_id
  validates :due_by, presence: true

  def self.searchfor(user_fname,user_sname,show_name)
    userIDs = User.where("first_name LIKE ? AND last_name LIKE ?","%#{user_fname}%","%#{user_sname}%").ids
    showIDs = Show.where("name LIKE ?","%#{show_name}%")
    return self.where(user_id: userIDs, show_id: showIDs)
  end

  def convert_to_staffing_debt()
    staffingDebt = Admin::StaffingDebt.new
    staffingDebt.due_by = self.due_by
    staffingDebt.show_id = self.show_id
    staffingDebt.user_id = self.user_id
    staffingDebt.converted = true
    staffingDebt.save!
    self.destroy
  end

end
