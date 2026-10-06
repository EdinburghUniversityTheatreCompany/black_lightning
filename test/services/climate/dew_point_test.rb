require "test_helper"

class Climate::DewPointTest < ActiveSupport::TestCase
  test "matches the published value at 20 C and 50 percent relative humidity" do
    # The textbook worked example: 20 °C / 50 % RH is a dew point just over 9 °C.
    assert_in_delta 9.26, Climate::DewPoint.celsius(temperature_c: 20, relative_humidity: 50), 0.05
  end

  test "equals the temperature at 100 percent relative humidity" do
    # Saturated air is at its own dew point: the formula's one exactly-known fixed
    # point, so the sharpest check on the coefficients.
    assert_in_delta 12.0, Climate::DewPoint.celsius(temperature_c: 12, relative_humidity: 100), 0.01
  end

  test "is below the temperature whenever the air is not saturated" do
    assert_operator Climate::DewPoint.celsius(temperature_c: 15, relative_humidity: 80), :<, 15
  end

  test "rises with humidity at a fixed temperature" do
    damp = Climate::DewPoint.celsius(temperature_c: 12, relative_humidity: 90)
    dry = Climate::DewPoint.celsius(temperature_c: 12, relative_humidity: 40)

    assert_operator damp, :>, dry
  end

  test "handles sub-zero temperatures" do
    # γ = ln(0.75) + (17.625 × -5)/(243.04 - 5) = -0.65787; Td = 243.04γ/(17.625 - γ) = -8.75.
    # Water coefficients throughout: below freezing the frost point is the
    # physically distinct quantity, but weather sources (Open-Meteo included)
    # report dew point over water, so this keeps indoor and outdoor on one scale.
    assert_in_delta(-8.75, Climate::DewPoint.celsius(temperature_c: -5, relative_humidity: 75), 0.05)
  end

  test "returns nil at zero relative humidity rather than negative infinity" do
    # ln(0) is -Infinity, which would sail through a decimal column as garbage.
    assert_nil Climate::DewPoint.celsius(temperature_c: 20, relative_humidity: 0)
  end

  test "returns nil when either reading is missing" do
    assert_nil Climate::DewPoint.celsius(temperature_c: nil, relative_humidity: 50)
    assert_nil Climate::DewPoint.celsius(temperature_c: 20, relative_humidity: nil)
  end

  test "treats a humidity above 100 as saturated instead of going above the temperature" do
    # 101 % is a miscalibrated sensor; clamping keeps dew point <= temperature.
    assert_in_delta 12.0, Climate::DewPoint.celsius(temperature_c: 12, relative_humidity: 101), 0.01
  end

  test "accepts BigDecimal readings straight off an ActiveRecord column" do
    result = Climate::DewPoint.celsius(temperature_c: BigDecimal("20.00"),
                                       relative_humidity: BigDecimal("50.00"))

    assert_in_delta 9.26, result, 0.05
  end
end
