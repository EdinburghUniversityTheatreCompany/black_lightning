class AdminController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_backend!
  before_action :check_consented!, if: :user_signed_in?

  layout 'admin'

  private

  def authorize_backend!
    authorize! :access, :backend
  end

  # Check if the user has consented before every request.
  def check_consented!
    return if current_user.consented?

    exception = CanCan::AccessDenied.new(t('errors.not_consented'))

    render_error_page(exception, 'errors/not_consented', 403)
    return false
  end
end
