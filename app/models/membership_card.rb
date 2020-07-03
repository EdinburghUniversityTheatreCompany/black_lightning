# == Schema Information
#
# Table name: membership_cards
#
# *id*::          <tt>integer, not null, primary key</tt>
# *card_number*:: <tt>string(255)</tt>
# *user_id*::     <tt>integer</tt>
# *created_at*::  <tt>datetime, not null</tt>
# *updated_at*::  <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
class MembershipCard < ApplicationRecord
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
    date_i = Time.now.to_i.to_s

    self.card_number = date_i + number
  end
  # :nocov:
end
