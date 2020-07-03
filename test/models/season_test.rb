# == Schema Information
#
# Table name: events
#
# *id*::                     <tt>integer, not null, primary key</tt>
# *name*::                   <tt>string(255)</tt>
# *tagline*::                <tt>string(255)</tt>
# *slug*::                   <tt>string(255)</tt>
# *description*::            <tt>text(65535)</tt>
# *xts_id*::                 <tt>integer</tt>
# *created_at*::             <tt>datetime, not null</tt>
# *updated_at*::             <tt>datetime, not null</tt>
# *is_public*::              <tt>boolean</tt>
# *image_file_name*::        <tt>string(255)</tt>
# *image_content_type*::     <tt>string(255)</tt>
# *image_file_size*::        <tt>integer</tt>
# *image_updated_at*::       <tt>datetime</tt>
# *start_date*::             <tt>date</tt>
# *end_date*::               <tt>date</tt>
# *venue_id*::               <tt>integer</tt>
# *season_id*::              <tt>integer</tt>
# *author*::                 <tt>string(255)</tt>
# *type*::                   <tt>string(255)</tt>
# *price*::                  <tt>string(255)</tt>
# *spark_seat_slug*::        <tt>string(255)</tt>
# *maintenance_debt_start*:: <tt>date</tt>
# *staffing_debt_start*::    <tt>date</tt>
# *proposal_id*::            <tt>integer</tt>
#--
# == Schema Information End
#++
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
