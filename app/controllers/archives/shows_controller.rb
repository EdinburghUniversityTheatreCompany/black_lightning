class Archives::ShowsController < ArchivesController
  def index
    @shows = ::Show.paginate(:page => params[:page], :per_page => 5).where(:is_public => true)

    if @search_start_date && @search_end_date
      @shows = @shows.where(:start_date => @search_start_date..@search_end_date)
    end

    if @search_name
      q = "%#{@search_name}%"
      @shows = @shows.where("name like ?", q)
    end

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @shows }
    end
  end
end