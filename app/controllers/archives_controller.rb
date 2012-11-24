class ArchivesController < ApplicationController
  layout "archives"
  
  before_filter :check_select_date, :except => [:set_date]
  
  def set_date
    if params[:target]
      redirect_to send('archives_' + params[:target] + '_index_path', params[:start_month], params[:start_year], params[:end_month], params[:end_year])
    else
      redirect_to archives_index_path(params[:start_month], params[:start_year], params[:end_month], params[:end_year])
    end
  end
  
  def index
  end
  
  private
  def check_select_date
    unless request.env['PATH_INFO'] == archives_index_path
      unless params[:start_month] && params[:start_year] && params[:end_month] && params[:end_year]
        redirect_to archives_index_path(01, 1.years.ago.year, 12, Date.today.year)
        return
      end
      
      start_yr = Integer(params[:start_year])
      start_mnth = Integer(params[:start_month])
      end_yr = Integer(params[:end_year])
      end_mnth = Integer(params[:end_month])
      
      @search_start_date = ::Date.new(start_yr, start_mnth, 1)
      @search_end_date = ::Date.new(end_yr, end_mnth, Time.days_in_month(end_mnth))
    end
  end
end