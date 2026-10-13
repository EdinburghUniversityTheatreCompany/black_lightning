##
# Renders the error pages config.exceptions_app re-dispatches to ("/<status>") for an exception
# no controller rescued: one raised in middleware, or while rendering an error page.
##
class ErrorsController < ApplicationController
  skip_authorization_check
  skip_before_action :require_profile_completion!

  DEFAULT_STATUS = 500

  # Anything without a page of its own falls back to the 500 one, as Rails' PublicExceptions does.
  TEMPLATES = Hash.new("errors/500").merge(404 => "errors/404", 422 => "errors/422").freeze

  def show
    @exception_backtrace = exception.backtrace

    render_error_page(exception, TEMPLATES[status], status)
  end

  private

  # Rails re-dispatches to the status it decided on, so the path is the status.
  def status
    code = params[:status].to_i

    code.between?(400, 599) ? code : DEFAULT_STATUS
  end

  # Nothing sets the exception when the path was typed into the address bar, and the error page is
  # built around one.
  def exception
    @exception ||= request.env["action_dispatch.exception"] ||
                   StandardError.new(Rack::Utils::HTTP_STATUS_CODES.fetch(status, "Error"))
  end
end
