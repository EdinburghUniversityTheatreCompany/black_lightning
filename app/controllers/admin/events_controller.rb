# For the few things that are shared between the controllers of the events.

class Admin::EventsController < AdminController
  include GenericController

  load_and_authorize_resource find_by: :slug

  def index
    @events = load_index_resources

    if params[:commit] == 'Random'
      redirect_to(Event.find(@events.pluck(:id).sample))
      return
    end

    respond_to do |format|
      format.html { render 'admin/events/index' }
      format.json { render json: @events }
    end
  end

  private

  def order_args
    # Dealt with by default scope.
    nil
  end

  def permitted_params
    return Event.base_permitted_params
  end

  def should_paginate
    params.nil? || params[:commit] != 'Random'
  end
end
