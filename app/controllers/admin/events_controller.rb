class Admin::EventsController < Admin::GenericEventsController
  def index
    @editable_block_name = 'Events Admin Description'
    @url = :admin_events

    super
  end
end
