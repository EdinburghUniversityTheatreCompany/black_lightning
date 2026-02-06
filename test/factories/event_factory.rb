# == Schema Information
#
# Table name: events
#
# *id*::                     <tt>integer, not null, primary key</tt>
# *name*::                   <tt>string(255)</tt>
# *tagline*::                <tt>string(255)</tt>
# *slug*::                   <tt>string(255)</tt>
# *publicity_text*::         <tt>text(65535)</tt>
# *members_only_text*::      <tt>text(65535)</tt>
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

FactoryBot.define do
  factory :event do
    name         { generate(:random_name) }
    slug         { name.to_url }
    tagline      { "The tagline for #{name}" }
    publicity_text { "And a publicity text for #{name}" }
    content_warnings { [ nil, "Some content warnings for #{name}" ].sample }
    start_date   { generate(:random_date) }
    end_date     { start_date + 5.days }
    is_public    { [ true, false ].sample }
    pretix_shown { [ true, false ].sample }
    pretix_view  { [ "list", "week", "month" ].sample }

    # Use fixture venue - fixtures are loaded in tests
    venue_id { Venue.first&.id }

    transient do
      team_member_count { 0 }
      video_link_count { 0 }
      picture_count { 0 }
      attach_image { false }
      attach_proposal { false }
      tag_count { 0 }
      review_count { 0 }
    end

    trait :with_associations do
      team_member_count { 5 }
      video_link_count { rand(3) }
      picture_count { rand(3) }
      attach_image { true }
      attach_proposal { [ true, false ].sample }
      tag_count { 1 }
      review_count { 3 }
    end

    image { Rack::Test::UploadedFile.new(Rails.root.join("test", "test.png"), "image/png") if attach_image }

    after(:create) do |event, evaluator|
      create_list(:team_member, evaluator.team_member_count, teamwork: event)
      create_list(:video_link, evaluator.video_link_count, item: event)
      create_list(:picture, evaluator.picture_count, gallery: event)

      create_list(:review, evaluator.review_count, event: event)

      event.event_tags << EventTag.all.sample(evaluator.tag_count)

      event.proposal = FactoryBot.create(:proposal) if evaluator.attach_proposal && event.proposal.nil?
      event.save
    end
  end

  factory :show, parent: :event, class: Show do
    author { generate(:random_name) }
    price { generate(:random_name) }

    transient do
      feedback_count { 0 }
    end

    after(:create) do |show, evaluator|
      create_list(:feedback, evaluator.feedback_count, show: show) if evaluator.feedback_count > 0
    end

    trait :with_feedback do
      feedback_count { 1 }
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
