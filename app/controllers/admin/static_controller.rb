##
# Responsible for static pages in the admin section.
##
class Admin::StaticController < AdminController
  def committee
    unless current_user.present? && current_user.has_role?('Committee')
      raise(CanCan::AccessDenied, 'You are not on committee')
      return
    end
  end

  def bootstrap_test
  end

  # This is a catch-all for the pages that do not have explicitly defined routes.
  def error
    Rails.logger.error "ADMIN: Could not find the page at #{request.fullpath}"

    raise(ActionController::RoutingError.new('This page could not be found.'))
  end
end
