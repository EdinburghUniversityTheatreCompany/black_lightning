##
# Public controller for News. More details can be found there.
#
# Uses Will_Paginate for pagination.
##

class NewsController < ApplicationController
  load_and_authorize_resource
  ##
  # GET /news
  #
  # GET /news.json
  ##
  def index
    @title = 'Bedlam News'
    @news = @news.order('publish_date DESC').paginate(page: params[:page], per_page: 5)

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @news }
      format.rss { render layout: false }
    end
  end

  ##
  # GET /news/1
  #
  # GET /news/1.json
  ##
  def show
    @title = @news.title
    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @news }
    end
  end
end
