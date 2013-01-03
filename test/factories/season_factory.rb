# == Schema Information
#
# Table name: seasons
#
# *id*::          <tt>integer, not null, primary key</tt>
# *name*::        <tt>string(255)</tt>
# *description*:: <tt>text</tt>
# *start_date*::  <tt>date</tt>
# *end_date*::    <tt>date</tt>
# *created_at*::  <tt>datetime, not null</tt>
# *updated_at*::  <tt>datetime, not null</tt>
# *slug*::        <tt>string(255)</tt>
#--
# == Schema Information End
#++

FactoryGirl.define do
  factory :season do
    name        { generate(:random_string) }
    slug         { name.gsub(/\s+/,'-').gsub(/[^a-zA-Z0-9\-]/,'').downcase.gsub(/\-{2,}/,'-') }

    description { generate(:random_text) }

    start_date  { generate(:random_date) }
    end_date    { start_date.advance(:days => rand(3..6)) }

    ignore do
      event_count 0
      show_count  0
    end

    after(:create) do |season, evaluator|
      create_list(:event, evaluator.event_count, season: season)
      create_list(:show, evaluator.show_count, season: season)
    end
  end
end
