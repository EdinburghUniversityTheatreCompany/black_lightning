class StaticController < ApplicationController
  skip_authorization_check
  
  # This is a catch-all for the pages that do not have explicitly defined routes.
  def show
    begin
      render "static/#{params[:page]}"
    rescue
      render_404
    end
  end

  def home
    @news = News.accessible_by(current_ability).includes(image_attachment: :blob).order('publish_date DESC').first(2)
    @shows = Show.includes(image_attachment: :blob).current.order('start_date ASC')
    @last_show = Show.last_event
  end

  def render_404
    @meta['ROBOTS'] = 'NOINDEX, NOFOLLOW'

    respond_to do |type|
      type.html { render template: 'static/404', status: 404, layout: helpers.current_environment(request.fullpath) }
      type.all  { render body: nil, status: 404 }
    end
  end
end
