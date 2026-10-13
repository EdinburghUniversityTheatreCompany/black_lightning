module Climate
  ##
  # Which palette slot a sensor's line gets. Colour follows the SENSOR, not its
  # position in a selection, so deactivating one does not repaint the others and
  # a sensor is the same colour on every chart. Ranking by id across ALL sensors
  # is stable under exactly the filtering the chart lists do.
  class SeriesColors
    def index_for(sensor) = ids.index(sensor.id) || 0

    private

    def ids = @ids ||= Sensor.order(:id).pluck(:id)
  end
end
