class Archives::ShowsController < ArchivesController
  def index
    @q = Show.search(params[:q])
    @shows = @q.result(distinct: true)
               .paginate(:page => params[:page], :per_page => 5)
               .where(:is_public => true)

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @shows, methods: [:thumb_image, :slideshow_image] }
    end
  end
end