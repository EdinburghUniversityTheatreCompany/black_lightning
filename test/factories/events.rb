FactoryGirl.define do
  factory :event do
    name         { generate(:random_name) }
    slug         { name.gsub(/\s+/,'-').gsub(/[^a-zA-Z0-9\-]/,'').downcase.gsub(/\-{2,}/,'-') }
    tagline      { "The tagline for #{name}" }
    description  { "And a description for #{name}" }
    start_date   { Time.at(rand * Time.now.to_i) }
    end_date     { start_date + 5.days }
    is_public    { [true, false].sample }
  end

  factory :show, parent: :event, class: Show do
  end
end