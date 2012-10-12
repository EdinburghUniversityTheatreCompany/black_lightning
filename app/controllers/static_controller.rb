class StaticController < ApplicationController
  skip_authorization_check
  def home
  end
  
  def about
  end
end
