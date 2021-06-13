class Archives::EventsController < Archives::GenericEventsController
  def index
    @url = :archives_events

    super
  end
end
