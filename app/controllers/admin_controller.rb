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

  # Methods tried, in order, to name the record a URL segment identifies.
  BREADCRUMB_NAME_METHODS = %i[to_label display_title name title].freeze

  def add_breadcrumbs
    add_breadcrumb "Home", :admin_path

    full_working_path = "/admin"

    (@current_path.split("/")[2..] || []).each do |segment|
      full_working_path += "/#{segment}"

      # A Proc, resolved at render time: this before_action runs before the subclass loads the record.
      add_breadcrumb ->(view) { breadcrumb_name_for(view, segment) }, full_working_path
    end
  end

  # A segment that is the loaded record's id would read "Budgets / 12 / Edit", so name the record.
  def breadcrumb_name_for(view, segment)
    record = view.instance_variable_get("@#{controller_name.singularize}")

    return segment.titleize unless record.respond_to?(:to_param) && record.to_param.to_s == segment

    name_method = BREADCRUMB_NAME_METHODS.find do |method|
      record.respond_to?(method) && record.public_send(method).present?
    end

    name_method ? record.public_send(name_method).to_s : segment.titleize
  end
end
