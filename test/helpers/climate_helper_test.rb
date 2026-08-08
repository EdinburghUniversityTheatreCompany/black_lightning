require "test_helper"

class ClimateHelperTest < ActionView::TestCase
  include ClimateHelper

  def summary(hours_with_readings:, hours_at_risk:, longest_spell_hours: 0, longest_spell_ended_at: nil)
    { id: 1, name: "Crypt", hours_with_readings: hours_with_readings,
      hours_at_risk: hours_at_risk, longest_spell_hours: longest_spell_hours,
      longest_spell_ended_at: longest_spell_ended_at, days: [] }
  end

  test "says so plainly when nothing came close" do
    sentence = climate_risk_sentence(summary(hours_with_readings: 512, hours_at_risk: 0))

    assert_match(/512 hours with readings/, sentence)
    assert_match(/none/i, sentence)
  end

  # The denominator is hours with readings, never hours in the range.
  test "quotes the at-risk count against the hours that have readings" do
    sentence = climate_risk_sentence(summary(hours_with_readings: 512, hours_at_risk: 41,
                                             longest_spell_hours: 14,
                                             longest_spell_ended_at: Time.zone.parse("2026-03-03 09:00")))

    assert_match(/41 of the 512 hours with readings/, sentence)
    assert_match(/8%/, sentence)
    assert_match(/longest unbroken spell was 14 hours/, sentence)
  end

  test "says there is nothing to report when the sensor has no readings" do
    assert_match(/No readings/i, climate_risk_sentence(summary(hours_with_readings: 0, hours_at_risk: 0)))
  end

  test "does not mention a spell when there was not one" do
    sentence = climate_risk_sentence(summary(hours_with_readings: 10, hours_at_risk: 0))

    assert_no_match(/spell/, sentence)
  end
end
