class Archives::ShowsController < Archives::GenericEventsController
  def index
    @url = :archives_shows

    super
  end
end
