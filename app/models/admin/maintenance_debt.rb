class Admin::MaintenanceDebt < ActiveRecord::Base

  belongs_to :user
  belongs_to :show

  validates :dueBy, presence: true

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
