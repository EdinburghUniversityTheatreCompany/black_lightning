class Admin::SeasonsController < AdminController
  include GenericController

  load_and_authorize_resource find_by: :slug

  # GET /admin/seasons
  # GET /admin/seasons.json
  def index
    @title = 'Seasons'

    @editable_block_name = 'Seasons (Members Face)'
    @url = :admin_seasons

    @q = @seasons.ransack(params[:q])
    @events = @q.result(distinct: true)
                .accessible_by(current_ability)
                .paginate(page: params[:page], per_page: 15)

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
    return Event.base_permitted_params + [
      event_ids: []
    ]
  end
end
