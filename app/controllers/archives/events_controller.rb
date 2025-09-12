class Archives::EventsController < Archives::GenericEventsController
  def index
    super

    @title = "Event Archive"
    @url = :archives_events
  end
end
