class Admin::NavbarComponentPreview < ViewComponent::Preview
  layout "admin_new"

  def default
    render Admin::NavbarComponent.new(current_user: User.first)
  end
end
