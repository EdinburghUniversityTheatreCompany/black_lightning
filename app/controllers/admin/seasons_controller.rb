class Admin::SeasonsController < Admin::GenericEventsController
  # GET /admin/seasons
  # GET /admin/seasons.json

  private

  def permitted_params
    return super + [
      event_ids: []
    ]
  end
end
