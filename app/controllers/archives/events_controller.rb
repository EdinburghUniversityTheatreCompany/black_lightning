class Archives::EventsController < Archives::GenericEventsController
  def index
    super

    @title = "Event Archive"
    @url = :archives_events
  end

  private

  def index_description
    "Every production the Edinburgh University Theatre Company has staged at Bedlam Theatre, searchable by year, author, company and venue."
  end
end
