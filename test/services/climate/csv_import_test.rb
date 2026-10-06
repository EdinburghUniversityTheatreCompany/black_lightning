require "test_helper"

class Climate::CsvImportTest < ActiveSupport::TestCase
  # The shape Govee Home emails: UTF-8 BOM, sampling prose in the timestamp
  # header, stray space after the first comma.
  REAL_EXPORT = "﻿Timestamp for sample frequency every 15 min min, Temperature_Celsius,Relative_Humidity\n" \
                "2026-08-06 09:22:00,24.6,53.7\n" \
                "2026-08-06 09:37:00,20,63.4\n" \
                "2026-08-06 09:52:00,17.8,69.6\n".freeze

  def import(text) = Climate::CsvImport.new(text)

  test "parses the real Govee export, BOM and all" do
    # Unstripped, the BOM makes the first header unmatchable.
    result = import(REAL_EXPORT)

    assert_predicate result, :valid?
    assert_equal 3, result.rows.size
    assert_equal Climate::CsvImport::UNIT_CELSIUS, result.unit
    assert_in_delta 24.6, result.rows.first[:temperature_c], 0.001
    assert_in_delta 53.7, result.rows.first[:relative_humidity], 0.001
    assert_in_delta 20.0, result.rows.second[:temperature_c], 0.001 # written without a decimal point
  end

  test "reads timestamps in the application zone" do
    # The export carries naive local wall-clock, no offset. Reading it as UTC
    # would shift every crypt reading an hour through BST.
    row = import(REAL_EXPORT).rows.first

    assert_equal Time.zone.parse("2026-08-06 09:22:00"), row[:recorded_at]
  end

  test "detects Fahrenheit from the header, converts to Celsius and keeps the raw value" do
    # The export names whatever unit the app displays, hence read, not assumed.
    text = "Timestamp,Temperature_Fahrenheit,Relative_Humidity\n2026-08-06 09:22:00,53.6,53.7\n"
    result = import(text)
    row = result.rows.first

    assert_equal Climate::CsvImport::UNIT_FAHRENHEIT, result.unit
    assert_in_delta 12.0, row[:temperature_c], 0.01
    assert_in_delta 53.6, row[:raw_temperature], 0.001
    assert_equal "F", row[:raw_temperature_unit]
  end

  test "refuses a file whose temperature unit it cannot identify" do
    # Refusing is the safe direction: a guessed unit stores Fahrenheit as Celsius.
    text = "Timestamp,Temperature,Relative_Humidity\n2026-08-06 09:22:00,24.6,53.7\n"
    result = import(text)

    assert_not result.valid?
    assert_match(/unit/i, result.errors.first)
  end

  test "refuses a file with a missing column, no content or no data rows" do
    [ "Temperature_Celsius,Relative_Humidity\n24.6,53.7\n",
      "Timestamp,Temperature_Celsius\n2026-08-06 09:22:00,24.6\n",
      "",
      "   \n",
      "Timestamp,Temperature_Celsius,Relative_Humidity\n" ].each do |text|
      assert_not import(text).valid?, text.inspect
    end
  end

  test "reports the row number of an unreadable line rather than dropping it silently" do
    text = "Timestamp,Temperature_Celsius,Relative_Humidity\n" \
           "2026-08-06 09:22:00,24.6,53.7\n" \
           "not-a-date,24.6,53.7\n"
    result = import(text)

    assert_equal 1, result.rows.size
    assert_equal 1, result.skipped.size
    assert_match(/3/, result.skipped.first) # the file's own line number
  end

  test "refuses a file over the row limit with one error, not one per surplus row" do
    original = Climate::CsvImport::MAX_ROWS
    silence_warnings { Climate::CsvImport.const_set(:MAX_ROWS, 2) }
    rows = (1..4).map { |minute| "2026-08-06 09:0#{minute}:00,14.6,53.7\n" }.join

    result = import("Timestamp,Temperature_Celsius,Relative_Humidity\n#{rows}")

    assert_not result.valid?
    assert_equal 1, result.errors.size
  ensure
    silence_warnings { Climate::CsvImport.const_set(:MAX_ROWS, original) }
  end

  test "skips a blank trailing line without complaint" do
    result = import("#{REAL_EXPORT}\n\n")

    assert_predicate result, :valid?
    assert_empty result.skipped
    assert_equal 3, result.rows.size
  end

  test "handles CRLF line endings" do
    assert_equal 3, import(REAL_EXPORT.gsub("\n", "\r\n")).rows.size
  end

  test "accepts a tab-separated export" do
    # Paste from a spreadsheet arrives tab-separated; the delimiter is sniffed.
    text = "Timestamp\tTemperature_Celsius\tRelative_Humidity\n2026-08-06 09:22:00\t24.6\t53.7\n"

    assert_equal 1, import(text).rows.size
  end

  test "is not confused by a duplicated timestamp" do
    # A daily export overlaps the previous one; dedup is the unique index's job,
    # not the parser's.
    text = "Timestamp,Temperature_Celsius,Relative_Humidity\n" \
           "2026-08-06 09:22:00,24.6,53.7\n" \
           "2026-08-06 09:22:00,24.6,53.7\n"

    assert_equal 2, import(text).rows.size
  end
end
