##
# Public controller for News. More details can be found there.
#
# Uses Will_Paginate for pagination.
##

class NewsController < ApplicationController
  include GenericController

  load_and_authorize_resource
  ##
  # GET /news
  #
  # GET /news.json
  ##
  def index
    @title = 'Bedlam News'
    @news = @news.includes(image_attachment: :blob)
                 .order('publish_date DESC')
                 .paginate(page: params[:page], per_page: 5)

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @news }
      format.rss { render layout: false }
    end
  end

    ##
    # Show is handled by the Generic Controller.
    ##
end
