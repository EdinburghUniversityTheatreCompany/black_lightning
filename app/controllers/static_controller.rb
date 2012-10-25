class StaticController < ApplicationController
  
  def access_denied
    respond_to do |format|
      format.html { render :status => 403 }
    end
  end
  
  def home
  end
  
  def about
  end
end
