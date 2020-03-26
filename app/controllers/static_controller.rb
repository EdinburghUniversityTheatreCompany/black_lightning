class StaticController < ApplicationController
  # This is a catch-all for the pages that do not have explicitly defined routes.
  def show 
    begin
      render "static/#{params[:page]}"
    rescue
      render_404
    end
  end

  def home
    if current_user
      @news = News.current.limit(2).all
    else
      @news = News.for_public.limit(2).all
    end
    @shows = Show.current_slideshow.limit(5).all
    @last_show = Show.last_show
  end

  def access_denied
    respond_to do |format|
      format.html { render status: 403 }
    end
  end

  def render_404
    @meta['ROBOTS'] = 'NOINDEX, NOFOLLOW'

    respond_to do |type|
      type.html { render template: 'static/404', status: 404, layout: 'application' }
      type.all  { render nothing: true, status: 404 }
    end
  end

  def render_500
    @meta['ROBOTS'] = 'NOINDEX, NOFOLLOW'

    respond_to do |type|
      type.html { render template: 'static/500', status: 500, layout: 'application' }
      type.json { render json: { error: flash[:error] }, status: 500 }
      type.all  { render nothing: true, status: 500 }
    end
  end
end
