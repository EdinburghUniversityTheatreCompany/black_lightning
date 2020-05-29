require 'securerandom'

class MembershipActivationToken < ApplicationRecord
  belongs_to :user
  before_validation :generate_token

  validates :token, uniqueness: true, presence: true

  # Manage means creating in this case, but there are two types of creation. There is nothing to read, and everyone can activate.
  DISABLED_PERMISSIONS = %w[create read update].freeze

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64
  end
end
