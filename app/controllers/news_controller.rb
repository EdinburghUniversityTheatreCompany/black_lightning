class NewsController < ApplicationController

  load_and_authorize_resource

  # GET /news
  # GET /news.json
  def index
    @news = News.paginate(:page => params[:page], :per_page => 5).public

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @news }
      format.rss { render :layout => false }
    end
  end

  # GET /news/1
  # GET /news/1.json
  def show
    @news = News.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @news }
    end
  end
end
