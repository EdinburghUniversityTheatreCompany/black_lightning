module Climate
  ##
  # Which palette slot a sensor's line gets.
  #
  # Colour follows the SENSOR, not its position in the selection, so
  # deactivating one must not repaint the others — and so a sensor is the same
  # colour on every chart on the page, which is what lets them be read
  # together. Ranking by id across ALL sensors is stable under exactly the
  # operation that filters those lists.
  class SeriesColors
    def initialize
      @ids = Sensor.order(:id).pluck(:id)
    end

    def index_for(sensor) = @ids.index(sensor.id) || 0
  end
end
