class Opportunity < ActiveRecord::Base
  belongs_to :creator,  class_name: User
  belongs_to :approver, class_name: User

  attr_accessible :approved, :approver_id, :creator_id, :description, :show_email, :title, :expiry_date

  scope :approved, where("approved = true AND expiry_date > ? ", Time.now )
end
