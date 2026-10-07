require "test_helper"

class Climate::SeriesColorsTest < ActiveSupport::TestCase
  include ClimateTestHelpers

  # Deactivating one sensor must not repaint the others.
  test "a sensor keeps its index when a lower-id sensor is left out" do
    first = create_climate_sensor(display_name: "North")
    second = create_climate_sensor(display_name: "South")

    colors = Climate::SeriesColors.new
    before = colors.index_for(second)
    assert_not_equal colors.index_for(first), before

    first.update!(active: false)

    assert_equal before, Climate::SeriesColors.new.index_for(second)
  end

  test "an unknown sensor falls back to the first colour" do
    sensor = create_climate_sensor
    colors = Climate::SeriesColors.new
    sensor.destroy

    assert_equal 0, colors.index_for(sensor)
  end
end
