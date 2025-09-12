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
    # Generic Controller does not handle rss, so check if this is an rss request first.
    if request.format.symbol == :rss
      respond_to do |format|
        format.rss { render layout: false }
      end

      return
    end

    super

    @title = "Bedlam News"
  end

    ##
    # Show is handled by the Generic Controller.
    ##

    private

    def includes_args
      [ image_attachment: :blob ]
    end

    def order_args
      [ "publish_date DESC" ]
    end

    def items_per_page
      10
    end
end
