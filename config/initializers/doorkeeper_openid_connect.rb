# frozen_string_literal: true

raise Exception.new, 'The configuration for openid_connect is not included in the secrets.yml file' unless Rails.application.secrets.openid_connect && Rails.application.secrets.openid_connect[:issuer]

Doorkeeper::OpenidConnect.configure do
  issuer Rails.application.secrets.openid_connect[:issuer]

  signing_key File.read("#{Rails.root}/config/openid_signing_key")

  subject_types_supported [:public]

  resource_owner_from_access_token do |access_token|
    # Example implementation:
    User.find_by(id: access_token.resource_owner_id)
  end

  auth_time_from_resource_owner do |resource_owner|
    # Example implementation:
    resource_owner.current_sign_in_at
  end

  reauthenticate_resource_owner do |resource_owner, return_to|
    # Example implementation:
    store_location_for resource_owner, return_to
    sign_out resource_owner
    redirect_to new_user_session_url
  end

  # Depending on your configuration, a DoubleRenderError could be raised
  # if render/redirect_to is called at some point before this callback is executed.
  # To avoid the DoubleRenderError, you could add these two lines at the beginning
  #  of this callback: (Reference: https://github.com/rails/rails/issues/25106)
  #   self.response_body = nil
  #   @_response_body = nil
  select_account_for_resource_owner do |resource_owner, return_to|
    self.response_body = nil
    @_response_body = nil

    # Example implementation:
    store_location_for resource_owner, return_to
    redirect_to account_select_url
  end

  subject do |resource_owner, application|
    # Example implementation:
    resource_owner.id

    # or if you need pairwise subject identifier, implement like below:
    # Digest::SHA256.hexdigest("#{resource_owner.id}#{URI.parse(application.redirect_uri).host}#{'your_secret_salt'}")
  end

  # Protocol to use when generating URIs for the discovery endpoint,
  # for example if you also use HTTPS in development
  # protocol do
  #   :https
  # end

  # Expiration time on or after which the ID Token MUST NOT be accepted for processing. (default 120 seconds).
  # expiration 600

  # Example claims:
  claims do
    claim :email do |resource_owner, scopes|
      scopes.exists?(:email) ? resource_owner.email : ''
    end

    claim :full_name do |resource_owner, scopes|
      scopes.exists?(:profile) ? resource_owner.name_or_default : ''
    end
    
    claim :last_name do |resource_owner, scopes|
      scopes.exists?(:profile) ? resource_owner.last_name : ''
    end
    
    claim :first_name do |resource_owner, scopes|
      scopes.exists?(:profile) ? resource_owner.first_name : ''
    end
  end
end
