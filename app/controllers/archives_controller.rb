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
        redirect_to archives_index_path, notice: 'You must select a date first'
        return
      end
      
      @search_start_date = ::Date.new(Integer(params[:start_year]), Integer(params[:start_month]), 1)
      @search_end_date = ::Date.new(Integer(params[:end_year]), Integer(params[:end_month]), 1)
    end
  end
end