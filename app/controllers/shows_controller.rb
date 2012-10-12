class ShowsController < ApplicationController
  skip_authorization_check
  def index
    @shows = Show.paginate(:page => params[:page], :per_page => 5)
  end

  def show
    @show = Show.find_by_slug(params[:id])
    @title = @show.name
    respond_to do |format|
      format.html
    end
  rescue ActiveRecord::RecordNotFound
    respond_to_not_found(:html)
  end
end
