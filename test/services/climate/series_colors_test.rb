require "test_helper"

class Climate::SeriesColorsTest < ActiveSupport::TestCase
  include ClimateTestHelpers

  # Colour follows the sensor, not its position in a selection: deactivating
  # one sensor must not repaint the others, and a sensor must be the same
  # colour on every chart on the page.
  test "a sensor keeps its index when a lower-id sensor is left out" do
    first = create_climate_sensor(display_name: "North")
    second = create_climate_sensor(display_name: "South")

    both = Climate::SeriesColors.new

    assert_equal both.index_for(second), Climate::SeriesColors.new.index_for(second)
    assert_not_equal both.index_for(first), both.index_for(second)
  end

  test "an unknown sensor falls back to the first colour" do
    sensor = create_climate_sensor
    colors = Climate::SeriesColors.new
    sensor.destroy

    assert_equal 0, colors.index_for(sensor)
  end
end
