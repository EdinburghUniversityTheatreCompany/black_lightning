require 'test_helper'

class EventTest < ActionView::TestCase
  include TimeHelper

  setup do
    @event = FactoryBot.create(:event)
  end

  test 'last_event' do
    old_season = FactoryBot.create(:show, start_date: @event.start_date.advance(years: -3))
    last_workshop = FactoryBot.create(:workshop, start_date: Date.today.advance(weeks: -3), is_public: true)
    assert_equal last_workshop, Event.last_event
    assert_equal last_workshop, Workshop.last_event
  end

  test 'selection_collection' do
    assert_equal [[@event.name, @event.id]], Event.selection_collection
  end

  test 'this_year' do
    this_year_show = FactoryBot.create(:show, start_date: Date.today)
    old_show = FactoryBot.create(:show, start_date: @event.start_date.advance(years: -3))
    future_workshop = FactoryBot.create(:workshop, start_date: Date.today.advance(years: 1))

    assert_includes Event.this_year, this_year_show
    assert_not_includes Event.this_year, old_show
    assert_not_includes Event.this_year, future_workshop
  end

  test 'thumb_image_url' do
    assert_includes @event.thumb_image_url, 'active_storage_default-events-'
  end

  test 'slideshow_image_url' do
    assert_includes @event.slideshow_image_url, 'active_storage_default-events-'
  end

  test 'date_range' do
    assert_equal time_range_string(@event.start_date, @event.end_date, true), @event.date_range(true)
  end

  test 'simultaneous seasons' do
    season = FactoryBot.create(:season)
    assert_includes season.simultaneous_seasons, season
    show = FactoryBot.create(:show, start_date: season.end_date.advance(days: -1))
    assert_includes show.simultaneous_seasons, season
  end

  test 'as_json' do
    @event.update!(venue: venues(:one), season: FactoryBot.create(:season))

    json = @event.as_json(include: [:season])

    assert json.is_a? Hash
    assert json.key? 'venue'
    assert json.key? 'season'
  end
end
