class AdminController < ApplicationController
  before_filter :authenticate_user!
  before_filter :authorize_backend!
  layout "admin"
  def index
  end
  
  def access_denied
  end
end
