require "test_helper"

class Climate::VentilationSeriesTest < ActiveSupport::TestCase
  include ClimateTestHelpers

  def build(crypt, selected: nil, from: "2026-08-01", to: "2026-08-07", outdoor: @outdoor)
    Climate::VentilationSeries.new(
      crypt_sensors: Array(crypt), outdoor_sensor: outdoor,
      range: Climate::DateRange.from_params({ from: from, to: to }), selected: selected
    )
  end

  setup { @outdoor = outdoor_climate_sensor }

  test "defaults to the coldest, reported as WORST, and an explicit choice wins" do
    warm = create_climate_sensor(display_name: "Warm", in_crypt: true)
    cold = create_climate_sensor(display_name: "Cold", in_crypt: true)
    create_climate_reading(sensor: warm, recorded_at: Time.zone.parse("2026-08-05 12:00"), temperature_c: 16.0)
    create_climate_reading(sensor: cold, recorded_at: Time.zone.parse("2026-08-05 12:00"), temperature_c: 9.0)

    default = build([ warm, cold ])

    assert_equal cold, default.sensor
    assert_equal Climate::VentilationSeries::WORST, default.selected_key

    chosen = build([ warm, cold ], selected: warm.id.to_s)

    assert_equal warm, chosen.sensor
    assert_nil chosen.notice
    assert_equal warm.id.to_s, chosen.selected_key
  end

  # Like DateRange's clamp, a fallback says so rather than silently showing something else.
  test "a sensor outside the crypt, or an unparseable one, falls back and says so" do
    crypt = create_climate_sensor(display_name: "Crypt", in_crypt: true)
    elsewhere = create_climate_sensor(display_name: "Dressing room", in_crypt: false)

    [ elsewhere.id.to_s, "haddock" ].each do |selected|
      subject = build([ crypt ], selected: selected)

      assert_equal crypt, subject.sensor, selected
      assert_equal Climate::VentilationSeries::NOT_IN_CRYPT, subject.notice, selected
      assert_equal Climate::VentilationSeries::WORST, subject.selected_key, selected
    end
  end

  test "draws crypt temperature, crypt dew point and outdoor dew point" do
    crypt = create_climate_sensor(display_name: "Crypt", in_crypt: true)
    create_climate_reading(sensor: crypt, recorded_at: Time.zone.parse("2026-08-05 12:00"),
                           temperature_c: 12.0, dew_point_c: 10.0)
    create_climate_reading(sensor: @outdoor, recorded_at: Time.zone.parse("2026-08-05 12:00"),
                           temperature_c: 18.0, dew_point_c: 6.0)

    series = build([ crypt ]).series

    assert_equal %w[crypt_temperature crypt_dew_point outdoor_dew_point], series.map { |line| line[:key] }
    assert_in_delta 12.0, series[0][:points].first[:value], 0.001
    assert_in_delta 10.0, series[1][:points].first[:value], 0.001
    assert_in_delta 6.0, series[2][:points].first[:value], 0.001
    assert_equal %w[solid muted dashed], series.pluck(:style)
  end

  test "draws the crypt on its own when there is no outdoor feed" do
    crypt = create_climate_sensor(in_crypt: true)
    create_climate_reading(sensor: crypt, recorded_at: Time.zone.parse("2026-08-05 12:00"))

    series = build([ crypt ], outdoor: nil).series

    assert_equal %w[crypt_temperature crypt_dew_point], series.map { |line| line[:key] }
  end

  test "returns nothing when no sensor is marked as being in the crypt" do
    subject = build([])

    assert_nil subject.sensor
    assert_empty subject.series
  end

  test "memoizes series so a second call issues no further queries" do
    crypt = create_climate_sensor(display_name: "Crypt", in_crypt: true)
    create_climate_reading(sensor: crypt, recorded_at: Time.zone.parse("2026-08-05 12:00"))
    create_climate_reading(sensor: @outdoor, recorded_at: Time.zone.parse("2026-08-05 12:00"))

    subject = build([ crypt ])
    subject.series

    query_count = 0
    callback = ->(*) { query_count += 1 }

    result = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      subject.series
    end

    assert_equal subject.series, result
    assert_equal 0, query_count
  end

  test "offers the worst case plus every crypt sensor" do
    north = create_climate_sensor(display_name: "North", in_crypt: true)
    south = create_climate_sensor(display_name: "South", in_crypt: true)

    options = build([ north, south ]).options

    assert_equal [ Climate::VentilationSeries::WORST, north.id.to_s, south.id.to_s ],
                 options.map(&:last)
  end
end
