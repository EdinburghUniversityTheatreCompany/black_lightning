class Archives::SeasonsController < Archives::GenericEventsController
  def index
    super

    @title = 'Seasons Archive'
    @url = :archives_seasons
  end
end
