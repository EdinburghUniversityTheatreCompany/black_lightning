class Archives::WorkshopsController < ArchivesController
  def index
    @q = Workshop.search(params[:q])
    @workshops = @q.result(distinct: true)
                 .paginate(page: params[:page], per_page: 5)
                 .where(is_public: true)

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @workshops }
    end
  end
end
