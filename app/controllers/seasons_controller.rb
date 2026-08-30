class SeasonsController < PublicGenericEventsController
  # GET /seasons/1
  def show
    @events = @season.events.reorder(:start_date).group_by { |event| l event.start_date, format: :longy }

    super
  end

  private

  def index_description
    "Festivals and seasons at Bedlam Theatre, from the Bedlam Fringe to Halfbaked and the Improverts' year-round run."
  end
end
