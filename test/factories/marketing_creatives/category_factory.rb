# == Schema Information
#
# Table name: marketing_creatives_categories
#
# *id*::              <tt>bigint, not null, primary key</tt>
# *name*::            <tt>string(255)</tt>
# *name_on_profile*:: <tt>string(255)</tt>
# *url*::             <tt>string(255)</tt>
# *created_at*::      <tt>datetime, not null</tt>
# *updated_at*::      <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
FactoryBot.define do
  factory :marketing_creatives_category, class: MarketingCreatives::Category do
    name { generate(:random_string) }
    url { name.to_url }

    name_on_profile { generate(:random_string) }

    image { Rack::Test::UploadedFile.new(Rails.root.join('test', 'test.png'), 'image/png') }
  end
end
