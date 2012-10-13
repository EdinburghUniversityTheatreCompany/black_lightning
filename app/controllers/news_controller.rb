class NewsController < ApplicationController
  # GET /news
  # GET /news.json
  def index
    # TODO: This will need updating when members are implemented
    @news = News.where(:show_public => true).all(:conditions => ["publish_date <= ?", Date.current])

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @news }
    end
  end

  # GET /news/1
  # GET /news/1.json
  def show
    @news = News.find(params[:id])
    
    # TODO: This will need updating when members are implemented
    if !@news.show_public then
        render :file => "public/401.html", :status => :unauthorized
        return
    end

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @news }
    end
  end
end
