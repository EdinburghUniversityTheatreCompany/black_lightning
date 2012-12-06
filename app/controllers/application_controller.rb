class ApplicationController < ActionController::Base
  protect_from_forgery

  before_filter :set_globals

  rescue_from Exception, :with => :report_500     unless Rails.env.development? || Rails.env.test?
  rescue_from StandardError, :with => :report_500 unless Rails.env.development? || Rails.env.test?

  rescue_from CanCan::AccessDenied do |exception|
    redirect_to static_path('access_denied'), :notice => exception.message
  end

  rescue_from ActiveRecord::RecordNotFound do |exception|
    flash[:notice] = exception.message
    raise ActionController::RoutingError.new('Not Found')
  end

  def authorize_backend!
    authorize! :access, :backend
  end

  def set_globals
    @base_url = request.protocol + request.host_with_port
    #Create the @meta hash
    @meta = {}
    @support_email = "it@bedlamtheatre.co.uk"
  end

  def report_500(ex)
    flash[:error] = ex.message
    flash[:error_path] = request.fullpath
    flash[:error_location] = ex.backtrace[0].gsub Rails.root.to_s, ""

    redirect_to '/500'
  end

end
