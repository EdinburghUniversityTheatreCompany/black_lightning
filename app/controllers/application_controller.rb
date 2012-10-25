class ApplicationController < ActionController::Base
  protect_from_forgery
  
  rescue_from CanCan::AccessDenied do |exception|
    redirect_to access_denied_path, :notice => exception.message
  end

  def authorize_backend!
    authorize! :access, :backend
  end
end
