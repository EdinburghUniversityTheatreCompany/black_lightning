class MembershipCard < ActiveRecord::Base
  belongs_to :user

  attr_accessible :card_number, :user
end
