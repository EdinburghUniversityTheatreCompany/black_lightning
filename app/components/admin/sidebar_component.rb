class Admin::SidebarComponent < ViewComponent::Base
  def initialize(nav_items:, current_user:, current_path:)
    @nav_items = nav_items
    @current_user = current_user
    @current_path = current_path
  end

  private

  def category_open?(category)
    category[:children]&.any? { |item| active_item?(item) }
  end

  def active_item?(item)
    @current_path.start_with?(item[:path] || "")
  end

  def user_display_name
    @current_user.first_name.presence || @current_user.email
  end
end
