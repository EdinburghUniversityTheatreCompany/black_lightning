class AdminController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_backend!
  before_action :check_consented!, if: :user_signed_in?
  before_action :add_breadcrumbs

  layout "admin"

  private

  def authorize_backend!
    authorize! :access, :backend
  end

  # Check if the user has consented before every request.
  def check_consented!
    return if current_user.consented?

    exception = CanCan::AccessDenied.new(t("errors.not_consented"))

    render_error_page(exception, "errors/not_consented", 403)
    false
  end

  def set_globals
    super

    @admin_site = true
  end

  def add_breadcrumbs
    add_breadcrumb "Home", :admin_path

    path_array = @current_path.split("/")[2..-1]
    full_working_path = "/admin"

    if path_array.is_a? Array
      path_array.each do |working_path|
        current_path_title = working_path.gsub(Regexp.union("_"), " ")
        current_path_title = working_path.titleize
        full_working_path += "/"+working_path

        add_breadcrumb current_path_title, full_working_path
      end
    elsif path_array.is_a? String
      path_title = path_array.gsub(Regexp.union("_"), " ")
      path_title = path_title.titleize

      add_breadcrumb path_title, @current_path
    end
  end
end
