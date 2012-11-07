class StaticController < ApplicationController
  
  def access_denied
    respond_to do |format|
      format.html { render :status => 403 }
    end
  end
  
  def home
    @news = News.all(:conditions => ["publish_date <= ? AND show_public = ?", Date.current, true], :order => "publish_date DESC")
    @shows = Show.all(:conditions => ["end_date >= ? AND is_public = ?", Date.current, true], :order => "start_date ASC", :limit => 5)
  end
  
  def about
  end
end
