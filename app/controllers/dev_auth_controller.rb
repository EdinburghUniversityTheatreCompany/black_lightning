class DevAuthController < ApplicationController
  skip_authorization_check

  before_action :ensure_local_environment!

  # GET /dev_auth/login?token=SECRET&redirect_to=/some/page
  def login
    unless params[:token] == ENV.fetch("DEV_AUTH_TOKEN", "claude-screenshot-token")
      head :unauthorized
      return
    end

    user = User.find_by(email: "unknown_claude@bedlamtheatre.co.uk")

    if user.nil?
      render plain: "Dev user not found. Run: bin/rails db:seed", status: :not_found
      return
    end

    sign_in(user)
    redirect_to(params[:redirect_to].presence || root_path, allow_other_host: false)
  end

  private

  def ensure_local_environment!
    head :not_found unless Rails.env.local?
  end
end
