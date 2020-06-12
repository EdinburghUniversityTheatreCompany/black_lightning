class Archives::WorkshopsController < ArchivesController
  def index
    @q = Workshop.ransack(params[:q])
    @workshops = @q.result(distinct: true)
                   .where(is_public: true)
                   .includes(image_attachment: :blob)
                   .paginate(page: params[:page], per_page: 5)
                 

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @workshops }
    end
  end
end
