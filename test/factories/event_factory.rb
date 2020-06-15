# == Schema Information
#
# Table name: events
#
# *id*::                 <tt>integer, not null, primary key</tt>
# *name*::               <tt>string(255)</tt>
# *tagline*::            <tt>string(255)</tt>
# *slug*::               <tt>string(255)</tt>
# *description*::        <tt>text</tt>
# *xts_id*::             <tt>integer</tt>
# *created_at*::         <tt>datetime, not null</tt>
# *updated_at*::         <tt>datetime, not null</tt>
# *is_public*::          <tt>boolean</tt>
# *image_file_name*::    <tt>string(255)</tt>
# *image_content_type*:: <tt>string(255)</tt>
# *image_file_size*::    <tt>integer</tt>
# *image_updated_at*::   <tt>datetime</tt>
# *start_date*::         <tt>date</tt>
# *end_date*::           <tt>date</tt>
# *venue_id*::           <tt>integer</tt>
# *season_id*::          <tt>integer</tt>
# *author*::             <tt>string(255)</tt>
# *type*::               <tt>string(255)</tt>
#--
# == Schema Information End
#++

FactoryBot.define do
  factory :event do
    name         { generate(:random_name) }
    slug         { name.to_url }
    tagline      { "The tagline for #{name}" }
    description  { "And a description for #{name}" }
    start_date   { generate(:random_date) }
    end_date     { start_date + 5.days }
    is_public    { [true, false].sample }

    transient do
      team_member_count { 5 }
      picture_count { rand(3) }
      attach_image { true }
    end

    after(:create) do |event, evaluator|
      create_list(:team_member, evaluator.team_member_count, teamwork: event)
      create_list(:picture, evaluator.picture_count, gallery: event)

      event.image.attach(io: File.open(Rails.root.join('test', 'test.png')), filename: 'test.png', content_type: 'image/png') if evaluator.attach_image && !event.image.attached?
    end
  end

  factory :show, parent: :event, class: Show do
    author { generate(:random_name) }
    price { generate(:random_name) }

    transient do
      review_count { 3 }
    end

    after(:create) do |show, evaluator|
      create_list(:review, evaluator.review_count, show: show)
    end
  end

  factory :workshop, parent: :event, class: Workshop do
  end

  factory :season, parent: :event, class: Season do
    transient do
      event_count { 0 }
      show_count { 0 }
      workshop_count { 0 }
    end

    after(:create) do |season, evaluator|
      create_list(:event, evaluator.event_count, season: season)
      create_list(:show, evaluator.show_count, season: season)
      create_list(:workshop, evaluator.workshop_count, season: season)
    end
  end
end
