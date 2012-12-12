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
    # Prevent redirect loop if 500 rendering fails.
    if request.env['PATH_INFO'] == static_path('500')
      Rails.logger.error "Could not render the 500 page:"
      Rails.logger.error ex

      return render :inline => "Sorry. Something has gone very wrong. We will try to fix this asap."
    end

    Rails.logger.warn  "Caught error and redirected to 500"
    Rails.logger.error ex

    flash[:error] = ex.message
    flash[:error_path] = request.fullpath
    flash[:error_location] = ex.backtrace[0].gsub Rails.root.to_s, ""

    redirect_to static_path('500', params[:format])
  end

end
