class Admin::WorkshopsController < Admin::GenericEventsController
  # GET /admin/shows
  # GET /admin/shows.json
  def index
    @title = 'Workshops and Events'
    
    @editable_block_name = 'Workshops (Members Face)'
    @url = :admin_workshops

    super
  end
end
