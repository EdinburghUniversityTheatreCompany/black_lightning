class Admin::MaintenanceDebt < ActiveRecord::Base

  belongs_to :user
  belongs_to :show


  validates :dueBy, presence: true

  def self.searchfor(user_fname,user_sname,show_name)
    #User.where("username LIKE ?","%cooke%")
    userIDs = User.where("first_name LIKE '%#{user_fname}%' AND last_name LIKE '%#{user_sname}%'").ids
    showIDs = Show.where("name LIKE '%#{show_name}%'")
    return self.where(user_id: userIDs, show_id: showIDs)
  end

  def convert_to_staffing_debt()
    sdebt = Admin::StaffingDebt.new
    sdebt.dueBy = self.dueBy
    sdebt.show_id = self.show_id
    sdebt.user_id = self.user_id
    sdebt.converted = true
    sdebt.save!
    self.destroy
  end

end
