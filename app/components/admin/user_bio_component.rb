class Admin::UserBioComponent < ViewComponent::Base
  def initialize(user:)
    @user = user
  end
end
