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

      # The name is a Proc so breadcrumbs_on_rails resolves it at RENDER time. It has to
      # be lazy: this before_action is declared on AdminController, so it runs before the
      # subclass's own set_<resource> / load_and_authorize_resource callbacks and the
      # record does not exist yet.
      add_breadcrumb ->(view) { breadcrumb_name_for(view, segment) }, full_working_path
    end
  end

  # A path segment that is a record identifier titleizes into nonsense: a budget edit page
  # read "Home / Reimbursements / Budgets / 12 / Edit", and on the legacy Airtable ids
  # "Rec X Ko G9m U Fbu Dn5 A". When the segment is the identifier of the record the
  # controller loaded, use that record's own name instead.
  def breadcrumb_name_for(view, segment)
    record = view.instance_variable_get("@#{controller_name.singularize}")

    return segment.titleize unless record.respond_to?(:to_param) && record.to_param.to_s == segment

    name_method = BREADCRUMB_NAME_METHODS.find do |method|
      record.respond_to?(method) && record.public_send(method).present?
    end

    name_method ? record.public_send(name_method).to_s : segment.titleize
  end
end
