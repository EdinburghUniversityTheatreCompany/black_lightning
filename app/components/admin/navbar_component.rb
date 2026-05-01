class Admin::NavbarComponent < ViewComponent::Base
  def initialize(current_user:)
    @current_user = current_user
  end

  private

  def user_display_name
    @current_user.first_name.presence || @current_user.email
  end
end
