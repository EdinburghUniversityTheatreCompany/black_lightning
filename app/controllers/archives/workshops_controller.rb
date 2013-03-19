class Archives::WorkshopsController < ArchivesController
  def index
    @workshops = ::Workshop.paginate(:page => params[:page], :per_page => 5).where(:is_public => true)

    if @search_start_date && @search_end_date
      @workshops = @workshops.where(:start_date => @search_start_date..@search_end_date)
    end

    if @search_name
      q = "%#{@search_name}%"
      @workshops = @workshops.where("name like ?", q)
    end

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @workshops }
    end
  end
end