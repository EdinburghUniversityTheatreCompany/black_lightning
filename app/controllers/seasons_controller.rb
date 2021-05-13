class SeasonsController < GenericEventsController

  # GET /seasons/1
  def show
    @events = @season.events.reorder(:start_date).group_by { |event| l event.start_date, format: :longy }

    super
  end

  private

  def load_index_resources
    return super.current
  end
end
