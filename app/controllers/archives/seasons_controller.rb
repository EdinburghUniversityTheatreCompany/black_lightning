class Archives::SeasonsController < Archives::GenericEventsController
  def index
    super

    @title = "Seasons Archive"
    @url = :archives_seasons
  end

  private

  def index_description
    "Every festival and season Bedlam Theatre has run, from the Bedlam Fringe to Halfbaked and the Improverts."
  end
end
