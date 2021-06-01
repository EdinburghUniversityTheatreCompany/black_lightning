class Archives::EventsController < Archives::GenericEventsController
  def index
    @url = :archives_events_index

    super
  end
end
