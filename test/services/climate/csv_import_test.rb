require "test_helper"

class Climate::CsvImportTest < ActiveSupport::TestCase
  # Byte-for-byte the shape Govee Home emails, including the UTF-8 BOM, the
  # sample-frequency prose in the timestamp header, and the stray space after
  # the first comma.
  REAL_EXPORT = "﻿Timestamp for sample frequency every 15 min min, Temperature_Celsius,Relative_Humidity\n" \
                "2026-08-06 09:22:00,24.6,53.7\n" \
                "2026-08-06 09:37:00,20,63.4\n" \
                "2026-08-06 09:52:00,17.8,69.6\n".freeze

  def import(text) = Climate::CsvImport.new(text)

  test "parses the real Govee export" do
    result = import(REAL_EXPORT)

    assert_predicate result, :valid?
    assert_equal 3, result.rows.size
  end

  test "reads timestamps in the application zone" do
    # The export carries naive local wall-clock, no offset. Reading it as UTC
    # would shift every crypt reading an hour through BST.
    row = import(REAL_EXPORT).rows.first

    assert_equal Time.zone.parse("2026-08-06 09:22:00"), row[:recorded_at]
  end

  test "reads temperature and humidity" do
    row = import(REAL_EXPORT).rows.first

    assert_in_delta 24.6, row[:temperature_c], 0.001
    assert_in_delta 53.7, row[:relative_humidity], 0.001
  end

  test "accepts an integer temperature written without a decimal point" do
    assert_in_delta 20.0, import(REAL_EXPORT).rows.second[:temperature_c], 0.001
  end

  test "strips the byte order mark so the first header is readable" do
    # Without stripping it the first header reads "﻿Timestamp…" and the
    # timestamp column is never found.
    assert_predicate import(REAL_EXPORT), :valid?
    assert_equal Climate::CsvImport::UNIT_CELSIUS, import(REAL_EXPORT).unit
  end

  # --- units -----------------------------------------------------------------

  test "detects Celsius from the header" do
    assert_equal Climate::CsvImport::UNIT_CELSIUS, import(REAL_EXPORT).unit
  end

  test "detects Fahrenheit from the header and converts to Celsius" do
    # The export names whatever unit the APP is set to display, which is the
    # whole reason this is read rather than assumed.
    text = "Timestamp,Temperature_Fahrenheit,Relative_Humidity\n2026-08-06 09:22:00,53.6,53.7\n"
    result = import(text)

    assert_equal Climate::CsvImport::UNIT_FAHRENHEIT, result.unit
    assert_in_delta 12.0, result.rows.first[:temperature_c], 0.01
  end

  test "keeps the raw Fahrenheit value and its unit for reversibility" do
    text = "Timestamp,Temperature_Fahrenheit,Relative_Humidity\n2026-08-06 09:22:00,53.6,53.7\n"
    row = import(text).rows.first

    assert_in_delta 53.6, row[:raw_temperature], 0.001
    assert_equal "F", row[:raw_temperature_unit]
  end

  test "refuses a file whose temperature unit it cannot identify" do
    # Guessing here is exactly the mistake the old verify-the-unit flow existed
    # to prevent; refusing is the safe direction.
    text = "Timestamp,Temperature,Relative_Humidity\n2026-08-06 09:22:00,24.6,53.7\n"
    result = import(text)

    assert_not result.valid?
    assert_match(/unit/i, result.errors.first)
  end

  # --- structure -------------------------------------------------------------

  test "refuses a file with no timestamp column" do
    text = "Temperature_Celsius,Relative_Humidity\n24.6,53.7\n"

    assert_not import(text).valid?
  end

  test "refuses a file with no humidity column" do
    text = "Timestamp,Temperature_Celsius\n2026-08-06 09:22:00,24.6\n"

    assert_not import(text).valid?
  end

  test "refuses an empty file" do
    assert_not import("").valid?
    assert_not import("   \n").valid?
  end

  test "refuses a file with headers but no data rows" do
    assert_not import("Timestamp,Temperature_Celsius,Relative_Humidity\n").valid?
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

  test "reports the covered range and sample count for the summary" do
    result = import(REAL_EXPORT)

    assert_equal Time.zone.parse("2026-08-06 09:22:00"), result.range.begin
    assert_equal Time.zone.parse("2026-08-06 09:52:00"), result.range.end
  end

  test "leaves dew point to the ingest rather than inventing a column" do
    assert_nil import(REAL_EXPORT).rows.first[:dew_point_c]
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
