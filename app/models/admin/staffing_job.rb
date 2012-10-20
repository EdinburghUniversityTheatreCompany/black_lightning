class Admin::StaffingJob < ActiveRecord::Base
  belongs_to :staffings, :class_name => "Admin::Staffing"
  has_one :user
  
  attr_accessible :name, :user, :user_id
end
