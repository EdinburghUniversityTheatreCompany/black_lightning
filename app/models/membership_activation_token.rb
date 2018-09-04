require 'securerandom'
class MembershipActivationToken < ActiveRecord::Base
  belongs_to :user
  before_validation :generate_token

  validates :token, presence: true

  def to_param
    token
  end

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64
  end
end
