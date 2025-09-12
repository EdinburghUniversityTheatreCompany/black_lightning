class Admin::WorkshopsController < Admin::GenericEventsController
  # GET /admin/shows
  # GET /admin/shows.json
  def index
    @title = "Workshops and Events"

    super
  end
end
