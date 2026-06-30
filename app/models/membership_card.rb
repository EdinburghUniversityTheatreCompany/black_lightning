# == Schema Information
#
# Table name: membership_cards
# Database name: primary
#
#  id          :integer          not null, primary key
#  card_number :string(255)
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  user_id     :integer
#
# Indexes
#
#  index_membership_cards_on_user_id  (user_id)
#
class MembershipCard < ApplicationRecord
  # Length validations enforcing database column limits
  validates :card_number, length: { maximum: 255 }
  before_create :set_card_number

  belongs_to :user

  # Unused
  # :nocov:
  def to_param
    card_number
  end

  def set_card_number
    return unless card_number.nil?

    # Generate a 4 digit random number...
    number = rand(9999).to_s.center(4, rand(9).to_s)

    # Get unix timestamp
    date_i = Time.current.to_i.to_s

    self.card_number = date_i + number
  end
  # :nocov:
end
