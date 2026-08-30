class Archives::ShowsController < Archives::GenericEventsController
  def index
    super

    @title = "Show Archive"
    @url = :archives_shows
  end

  private

  def index_description
    "Decades of plays and musicals staged by the EUTC at Bedlam Theatre \u2014 the full archive, back to the company's earliest recorded productions."
  end
end
