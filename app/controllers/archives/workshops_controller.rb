class Archives::WorkshopsController < Archives::GenericEventsController
  def index
    super

    @title = "Workshops Archive"
    @url = :archives_workshops
  end
end
