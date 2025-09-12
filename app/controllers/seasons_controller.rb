class SeasonsController < PublicGenericEventsController
  # GET /seasons/1
  def show
    @events = @season.events.reorder(:start_date).group_by { |event| l event.start_date, format: :longy }

    super
  end
end
