require 'test_helper'

class SeasonTest < ActionView::TestCase
  # The constraint is tested in the (non-admin) seasons controller test.

  test 'get season event suggestions' do
    season = FactoryBot.create(:season)

    part_of_season_but_outside_date_range = FactoryBot.create_list(:workshop, 2, start_date: season.end_date)
    included_events = [FactoryBot.create(:event, start_date: season.end_date), FactoryBot.create(:event, start_date: season.start_date)]
    _excluded_shows = FactoryBot.create_list(:show, 2, start_date: season.end_date.advance(days: 1))

    season.events = part_of_season_but_outside_date_range

    suggestions = season.simultaneous_events

    assert_equal (included_events + part_of_season_but_outside_date_range).to_set, suggestions.to_set
  end
end
