class Admin::NavbarComponent < ViewComponent::Base
  def initialize(title: nil, header_badges: [])
    @title = title
    @header_badges = header_badges || []
  end

  private

  def has_badges? = @header_badges.any?
end
