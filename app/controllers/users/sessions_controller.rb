class Users::SessionsController < Devise::SessionsController
  def create
    self.resource = warden.authenticate(auth_options)

    if resource
      set_flash_message!(:notice, :signed_in)
      sign_in(resource_name, resource)
      respond_with resource, location: after_sign_in_path_for(resource)
    else
      self.resource = resource_class.new(sign_in_params)
      resource.errors.add(:base, I18n.t("devise.failure.invalid", authentication_keys: resource_class.authentication_keys.first))
      render :new, status: :unprocessable_entity
    end
  end
end
