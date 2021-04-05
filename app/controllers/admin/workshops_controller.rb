class Admin::WorkshopsController < Admin::EventsController
  # GET /admin/shows
  # GET /admin/shows.json
  def index
    @editable_block_name = 'Workshops (Members Face)'
    @url = :admin_workshops

    super
  end
end
