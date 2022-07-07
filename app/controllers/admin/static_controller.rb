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
end
