class AdminController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_backend!
  layout 'admin'
  def index
    @title = 'Administration'
  end
end
