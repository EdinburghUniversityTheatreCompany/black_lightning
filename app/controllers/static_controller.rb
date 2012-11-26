class StaticController < ApplicationController

  def access_denied
    respond_to do |format|
      format.html { render :status => 403 }
    end
  end

  def home
    @news = News.all(:conditions => ["publish_date <= ? AND show_public = ?", Date.current, true], :order => "publish_date DESC")
    @shows = Show.current(:limit => 5)
  end

  def about
  end
end
