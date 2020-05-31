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
    @title = 'News'
    @news = @news.order('publish_date DESC').paginate(page: params[:page], per_page: 15)

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
    @title = 'Create News'

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @news }
    end
  end

  ##
  # GET /admin/news/1/edit
  ##
  def edit
    @title = "Edit #{@news.title}"
  end

  ##
  # POST /admin/news
  #
  # POST /admin/news.json
  ##
  def create
    @news.author = current_user

    respond_to do |format|
      if @news.save
        format.html { redirect_to [:admin, @news], notice: 'News was successfully created.' }
        format.json { render json: [:admin, @news], status: :created, location: @news }
      else
        format.html { render 'new', status: :unprocessable_entity }
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
    respond_to do |format|
      if @news.update(news_params)
        format.html { redirect_to [:admin, @news], notice: 'News was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render 'edit', status: :unprocessable_entity }
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
    helpers.destroy_with_flash_message(@news)

    respond_to do |format|
      format.html { redirect_to admin_news_index_url }
      format.json { head :no_content }
    end
  end

  private

  def news_params
    params.require(:news).permit(:publish_date, :show_public, :slug, :title, :body, :image)
  end
end
