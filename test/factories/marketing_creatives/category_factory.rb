FactoryBot.define do
  factory :marketing_creatives_category, class: MarketingCreatives::Category do
    name { generate(:random_string) }
    url { name.to_url }

    name_on_profile { generate(:random_string) }

    image { Rack::Test::UploadedFile.new(Rails.root.join('test', 'test.png'), 'image/png') }
  end
end
