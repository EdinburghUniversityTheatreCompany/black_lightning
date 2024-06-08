# == Schema Information
#
# Table name: membership_activation_tokens
#
# *id*::         <tt>integer, not null, primary key</tt>
# *uid*::        <tt>string(255)</tt>
# *token*::      <tt>string(255)</tt>
# *user_id*::    <tt>integer</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
require 'securerandom'

class MembershipActivationToken < ApplicationRecord
  belongs_to :user
  before_validation :generate_token

  validates :token, uniqueness: { case_sensitive: false }, presence: true

  # Manage means creating in this case, but there are two types of creation. There is nothing to read, and everyone can activate.
  DISABLED_PERMISSIONS = %w[create read update].freeze

  def to_param
    return token
  end

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64
  end
end
