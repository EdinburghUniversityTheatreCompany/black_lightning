##
# Public controller for News. More details can be found there.
#
# Uses paginate for pagination.
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
                 .page(params[:page]).per(5)

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
