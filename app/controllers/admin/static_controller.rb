##
# Responsible for static pages in the admin section.
##
class Admin::StaticController < AdminController
  # Gated by the `access committee` grid permission (ticked for the Committee role by the
  # 2026-09-05 migration), not by the role name, so a co-opted helper can be let in without
  # being made committee and a rename of the role cannot lock committee out.
  def committee
    authorize! :access, :committee
  end

  # This is a catch-all for the pages that do not have explicitly defined routes.
  def error
    Rails.logger.error "ADMIN: Could not find the page at #{request.fullpath}"

    raise(ActionController::RoutingError.new("This page could not be found."))
  end
end
