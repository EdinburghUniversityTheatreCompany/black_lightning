class Admin::NavbarComponentPreview < Admin::ApplicationComponentPreview
  def default
    render Admin::NavbarComponent.new(current_user: sample_user)
  end
end
