##
# Admin controller for News. More details can be found there.
##

class Admin::NewsController < AdminController

  load_and_authorize_resource

  ##
  # GET /admin/news
  #
  # GET /admin/news.json
  ##
  def index
    @title = "News"
    @news = News.all

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @news }
    end
  end

  ##
  # GET /admin/news/1
  #
  # GET /admin/news/1.json
  ##
  def show
    @news = News.find(params[:id])
    @title = @news.title
    respond_to do |format|
      format.html { render 'news/show' }
      format.json { render json: @news }
    end
  end

  ##
  # GET /admin/news/new
  #
  # GET /admin/news/new.json
  ##
  def new
    @news = News.new
    @title = "Create News"
    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @news }
    end
  end

  ##
  # GET /admin/news/1/edit
  ##
  def edit
    @news = News.find(params[:id])
    @title = "Edit #{@news.title}"
  end

  ##
  # POST /admin/news
  #
  # POST /admin/news.json
  ##
  def create
    @news = News.new(params[:news])
    @news.author = current_user

    respond_to do |format|
      if @news.save
        format.html { redirect_to [:admin, @news], notice: 'News was successfully created.' }
        format.json { render json: [:admin, @news], status: :created, location: @news }
      else
        format.html { render "new" }
        format.json { render json: @news.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # PUT /admin/news/1
  #
  # PUT /admin/news/1.json
  ##
  def update
    @news = News.find(params[:id])

    respond_to do |format|
      if @news.update_attributes(params[:news])
        format.html { redirect_to [:admin, @news], notice: 'News was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render "edit" }
        format.json { render json: @news.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # DELETE /admin/news/1
  #
  # DELETE /admin/news/1.json
  ##
  def destroy
    @news = News.find(params[:id])
    @news.destroy

    respond_to do |format|
      format.html { redirect_to admin_news_index_url }
      format.json { head :no_content }
    end
  end
end
