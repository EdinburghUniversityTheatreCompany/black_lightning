class Admin::NavbarComponent < ViewComponent::Base
  def initialize(current_user:, title: nil, header_badges: [])
    @current_user = current_user
    @title = title
    @header_badges = header_badges || []
  end

  private

  def has_badges? = @header_badges.any?
end
