class Admin::StaffingJob < ActiveRecord::Base
  belongs_to :staffing, :class_name => "Admin::Staffing"
  belongs_to :user
  
  attr_accessible :name, :user, :user_id
end
