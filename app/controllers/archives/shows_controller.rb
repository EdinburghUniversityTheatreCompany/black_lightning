class Archives::ShowsController < ArchivesController
  def index
    @shows = ::Show.paginate(:page => params[:page], :per_page => 5).where(:start_date => @search_start_date..@search_end_date)
    render "/shows/index"
  end
end