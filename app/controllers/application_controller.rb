class ApplicationController < ActionController::Base
  protect_from_forgery

  def authorize_backend!
    authorize! :access, :backend
  end
end
