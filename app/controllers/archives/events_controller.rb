class Archives::EventsController < Archives::GenericEventsController
  def index
    @search_url = :archives_events_index

    super
  end
end
