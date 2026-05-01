class Admin::NavbarComponentPreview < ViewComponent::Preview
  def default
    render Admin::NavbarComponent.new(current_user: User.first)
  end
end
