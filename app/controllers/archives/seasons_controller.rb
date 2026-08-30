class Archives::SeasonsController < Archives::GenericEventsController
  def index
    @title = "Seasons Archive"

    super
  end

  private

  def index_description
    "Every festival and season Bedlam Theatre has run since the company's earliest records, from the Bedlam Fringe to Halfbaked and the Improverts."
  end
end
