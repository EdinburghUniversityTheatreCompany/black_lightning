class MembershipCard < ActiveRecord::Base
  before_create :set_card_number

  belongs_to :user

  attr_accessible :card_number, :user

  def to_param
    card_number
  end

  def set_card_number
    return unless card_number.nil?

    # Generate a 4 digit random number...
    number = rand(9999).to_s.center(4, rand(9).to_s)

    # Get unix timestamp
    date_i = Time.now.to_i.to_s

    self.card_number = date_i + number
  end
end
