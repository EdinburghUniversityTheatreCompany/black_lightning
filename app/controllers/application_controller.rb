class ApplicationController < ActionController::Base
  include SubpageHelper, FormattingHelper, FlashHelper

  protect_from_forgery with: :exception
  before_action :set_paper_trail_whodunnit

  before_action :set_globals

  check_authorization unless: :devise_controller?

  rescue_from Exception, StandardError do |exception|
    if self.class.name.starts_with?("Doorkeeper::")
      raise exception
    end

    if Rails.env.production? || self.is_a?(Admin::TestsController) || self.is_a?(TestsController)
      report_500(exception)
    else
      # If we should not rescue, just raise the exception again.
      raise exception
    end
  end
  rescue_from CanCan::AccessDenied, with: :report_access_denied
  rescue_from ActiveRecord::RecordNotFound, ActionController::RoutingError, with: :report_404

  def set_globals
    @base_url = request.protocol + request.host_with_port
    @current_path = request.path

    # Create the @meta hash
    @meta = {
      description: "The Bedlam Theatre is a unique, entirely student run theatre in the heart of Edinburgh.",

      # facebook opengraph data:
      "og:url" => @base_url + request.fullpath,
      "og:image" => @base_url + helpers.image_path("BedlamLogoBW.png"),
      "og:title" => @title ? "#{@title} - Bedlam Theatre" : "Bedlam Theatre",

      "viewport" => "width=device-width, initial-scale=1"
    }

    @support_email = "it@bedlamtheatre.co.uk"

    @admin_site = false
  end

  ##
  # Error Reporting
  ##
  def report_500(exception)
    Honeybadger.notify(exception, context: {
      user_email: current_user&.email,
      user_name: current_user&.name_or_email
    }) if Rails.env.production?

    Rails.logger.warn "Caught error and redirected to 500"
    Rails.logger.error exception
    Rails.logger.error exception.backtrace

    @exception_backtrace = exception.backtrace

    render_error_page(exception, "errors/500", 500)
  end

  def report_access_denied(exception)
    render_error_page(exception, "errors/access_denied", 403)
  end

  def report_404(exception)
    render_error_page(exception, "errors/404", 404)
  end

  private

  def render_error_page(exception, template, status_code)
    @meta = {} if @meta.nil?
    @meta["ROBOTS"] = "NOINDEX, NOFOLLOW"

    # Prepares the flash by turning all messages into arrays and merging the 'alerts' into the 'errors'.
    standardise_flash

    # Add the current error that caused the application to halt to the error flash.
    # Compact removes any nil values.
    @error_messages = [ exception.message.gsub(Rails.root.to_s, "") ]
    @error_messages += flash[:error] if flash[:error].present?

    @error_type = exception.class

    # Errors and alerts are already rendered in the page body using the @error_summary, so we do not need to also render them as alerts.
    flash.delete(:error)
    flash.delete(:alert)

    respond_to do |type|
      type.html { render template: template, status: status_code, layout: helpers.current_environment(request.fullpath) }
      type.json { render json: { error: @error_messages }, status: status_code }
      type.all  { render body: nil, status: status_code }
    end
  end
end
