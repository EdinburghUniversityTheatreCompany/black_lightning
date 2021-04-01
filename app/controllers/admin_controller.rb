class AdminController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_backend!

  layout 'admin'

  def committee
    unless (current_user.present? && current_user.has_role?('Committee'))
      raise(CanCan::AccessDenied, 'You are not on committee')
      return
    end
  end

  private

  def authorize_backend!
    authorize! :access, :backend
  end
end
