class Admin::MaintenanceDebt < ActiveRecord::Base

  belongs_to :user
  belongs_to :show

  validates :dueBy, presence: true


end
