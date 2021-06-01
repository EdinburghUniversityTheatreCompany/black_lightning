class Archives::ShowsController < Archives::GenericEventsController
  def index
    @url = :archives_shows_index

    super
  end
end
