# == Schema Information
#
# Table name: admin_staffing_jobs
#
#  id          :integer          not null, primary key
#  name        :string(255)
#  staffing_id :integer
#  user_id     :integer
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#

class Admin::StaffingJob < ActiveRecord::Base
  belongs_to :staffing, :class_name => "Admin::Staffing"
  belongs_to :user

  validates :name, :presence => true

  attr_accessible :name, :user, :user_id
end
