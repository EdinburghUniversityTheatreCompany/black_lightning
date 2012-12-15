class StaticController < ApplicationController

  def home
    @news = News.public(:limit => 2)
    @shows = Show.current(:limit => 5)
  end

  def access_denied
    respond_to do |format|
      format.html { render :status => 403 }
    end
  end

  def render_404
    @meta["ROBOTS"] = "NOINDEX, NOFOLLOW"

    respond_to do |type|
      type.html { render :template => "static/404", :status => 404, :layout => 'application' }
      type.all  { render :nothing => true, :status => 404 }
    end
  end

  def render_500
    @meta["ROBOTS"] = "NOINDEX, NOFOLLOW"

    @email_body = "----------------------------\n\n Error Details:\n\n message: #{flash[:error]}\n\n Location: #{flash[:error_location]} \n\n url: #{flash[:error_path]}"

    respond_to do |type|
      type.html { render :template => "static/500", :status => 500, :layout => 'application' }
      type.json { render :json => {error: flash[:error]}, :status => 500 }
      type.all  { render :nothing => true, :status => 500 }
    end
  end
end
