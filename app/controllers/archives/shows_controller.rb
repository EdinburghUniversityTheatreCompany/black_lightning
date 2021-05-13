class Archives::ShowsController < Archives::GenericEventsController
  def index
    @search_url = :archives_shows_index

    super
  end
end
