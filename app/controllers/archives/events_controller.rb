class Archives::EventsController < Archives::GenericEventsController
  def index
    @title = "Event Archive"

    super
  end

  private

  def index_description
    "Every show, workshop and season the Edinburgh University Theatre Company has staged at Bedlam Theatre, searchable by year, author, company and venue."
  end
end
