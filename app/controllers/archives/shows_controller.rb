class Archives::ShowsController < ArchivesController
  def index
    @q = Show.ransack(params[:q])
    @shows = @q.result(distinct: true)
             .where(is_public: true)

    response.headers['X-Total-Count'] = @shows.count.to_s

    @shows = @shows.paginate(page: params[:page], per_page: 5)

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @shows, methods: [:thumb_image, :slideshow_image] }
    end
  end
end
