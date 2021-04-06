class AdminController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_backend!

  layout 'admin'

  private

  def authorize_backend!
    authorize! :access, :backend
  end
end
