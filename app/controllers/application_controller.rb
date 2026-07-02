class ApplicationController < ActionController::Base
  include SubpageHelper, FormattingHelper, FlashHelper

  protect_from_forgery with: :exception
  before_action :set_paper_trail_whodunnit
  before_action :configure_permitted_parameters, if: :devise_controller?

  before_action :set_globals
  before_action :require_profile_completion!
  around_action :set_statement_timeout

  check_authorization unless: :auth_controller?

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
      user_id: current_user&.id,
      user_email: current_user&.email,
      user_name: current_user&.name_or_email,
      path: request.fullpath,
      http_method: request.method,
      request_id: request.request_id
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

  helper_method :index_results_partial

  private

  # Partial used to render an index page's results list. Both the full-page index
  # wrapper and the turbo_stream (live-search) response render this, so they stay
  # in sync. Defaults to the controller's own partial; controllers that render a
  # shared index template (e.g. the event controllers, which all render
  # events/index) override this to point at the shared partial.
  def index_results_partial
    "#{controller_path}/index_results"
  end

  # Renders an index/list action's turbo_stream response safely.
  #
  # Live-search fetches (from live_search_controller) always carry q[...] params and want the
  # `fragment` (which updates an in-page container such as #index-results). But a Turbo
  # form-submission redirect (e.g. after #destroy) follows the 302 with the same turbo_stream Accept
  # header and NO q params; answering that with the fragment silently does nothing when the redirect
  # lands on a page without the target container (e.g. a show page), and the flash never shows. For a
  # paramless turbo_stream request, render the full HTML page so Turbo performs a real navigation.
  def render_index_stream_or_full(fragment:, full: "index")
    if params[:q].present?
      render fragment
    else
      render full, formats: :html, content_type: "text/html"
    end
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:account_update, keys: [ :calendar_email ])
  end

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

  def set_statement_timeout
    ActiveRecord::Base.connection.execute("SET SESSION max_execution_time = 25000")
    yield
  rescue ActiveRecord::StatementTimeout => e
    Honeybadger.notify(e, context: {
      path: request.path,
      method: request.method,
      query_string: request.query_string,
      user_id: current_user&.id
    })
    render_error_page(e, "errors/500", 500)
  end

  def require_profile_completion!
    return unless user_signed_in?
    return if current_user.profile_complete?
    return if profile_completion_exempt_controller?

    helpers.append_to_flash(:notice, "Please complete your profile to continue.")
    redirect_to profile_completion_path
  end

  def profile_completion_exempt_controller?
    is_a?(ProfileCompletionsController) || auth_controller?
  end

  def after_sign_in_path_for(resource)
    stored_location_for(resource) || admin_path
  end

  def auth_controller?
    devise_controller? ||
    is_a?(DevAuthController) ||
    is_a?(Doorkeeper::ApplicationController)
  end
end
