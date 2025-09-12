class Admin::SeasonsController < Admin::GenericEventsController
  # GET /admin/seasons
  # GET /admin/seasons.json

  private

  def permitted_params
    super + [
      event_ids: []
    ]
  end
end
