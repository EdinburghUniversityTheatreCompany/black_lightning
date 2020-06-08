require 'securerandom'

class MembershipActivationToken < ApplicationRecord
  belongs_to :user, optional: true
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
