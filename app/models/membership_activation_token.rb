class MembershipActivationToken < ActiveRecord::Base
  before_validation :generate_token

  validates :token, presence: true
  belongs_to :user

  def to_param
    token
  end

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64
  end
end