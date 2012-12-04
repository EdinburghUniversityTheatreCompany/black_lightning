class ApplicationController < ActionController::Base
  protect_from_forgery

  before_filter :set_globals

  rescue_from CanCan::AccessDenied do |exception|
    redirect_to static_path('access_denied'), :notice => exception.message
  end

  def authorize_backend!
    authorize! :access, :backend
  end

  def set_globals
    @base_url = request.protocol + request.host_with_port
    #Create the @meta hash
    @meta = {}
  end

end
