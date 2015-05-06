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

FactoryGirl.define do
  factory :event do
    name         { generate(:random_name) }
    slug         { name.gsub(/\s+/, '-').gsub(/[^a-zA-Z0-9\-]/, '').downcase.gsub(/\-{2,}/, '-') }
    tagline      { "The tagline for #{name}" }
    description  { "And a description for #{name}" }
    start_date   { generate(:random_date) }
    end_date     { start_date + 5.days }
    is_public    { [true, false].sample }
  end

  factory :show, parent: :event, class: Show do
    after(:create) do |show, _evaluator|
      create_list(:review, 3, show: show)
      create_list(:team_member, 5, teamwork: show)
    end
  end

  factory :workshop, parent: :event, class: Workshop do
  end
end
