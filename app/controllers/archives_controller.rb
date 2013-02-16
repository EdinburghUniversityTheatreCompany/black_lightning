class ArchivesController < ApplicationController
  layout "archives"

  before_filter :set_search_params

  def index
    @title = "Archives"
  end

  private
  def set_search_params
    if params[:start_date] && params[:end_date]
      if params[:start_date] != "" && params[:end_date] != ""
        @search_start_date = Chronic.parse(params[:start_date])
        @search_end_date   = Chronic.parse(params[:end_date])

        if @search_start_date.nil?
          flash[:alert] = "Error parsing start date."
        end

        if @search_end_date.nil?
          flash[:alert] = "Error parsing end date."
        end
      end
    end

    if params[:name]
      if params[:name] != ""
        @search_name = params[:name]
      end
    end
  end
end