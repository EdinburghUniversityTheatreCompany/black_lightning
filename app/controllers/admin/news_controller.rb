##
# Admin controller for News. More details can be found there.
##

class Admin::NewsController < AdminController
  include GenericController

  load_and_authorize_resource

  ##
  # GET /admin/news/1
  #
  # GET /admin/news/1.json
  ##
  def show
    respond_to do |format|
      # This one just renders the non-admin news, so not generic.
      format.html { render 'news/show' }
      format.json { render json: @news }
    end
  end

  ##
  # POST /admin/news
  #
  # POST /admin/news.json
  ##
  def create
    @news.author = current_user

    super
  end

  private

  def permitted_params
    [:publish_date, :show_public, :slug, :title, :body, :image]
  end

  def order_args
    ['publish_date DESC']
  end
end
