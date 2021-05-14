class Admin::SeasonsController < Admin::GenericEventsController
  # GET /admin/seasons
  # GET /admin/seasons.json
  def index
    @editable_block_name = 'Seasons (Members Face)'
    @url = :admin_seasons

    super
  end

  private

  def permitted_params
    return super + [
      event_ids: []
    ]
  end
end
