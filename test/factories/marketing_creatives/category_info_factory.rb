# == Schema Information
#
# Table name: marketing_creatives_category_infos
#
# *id*::          <tt>bigint, not null, primary key</tt>
# *profile_id*::  <tt>bigint</tt>
# *category_id*:: <tt>bigint</tt>
# *description*:: <tt>text(65535)</tt>
# *created_at*::  <tt>datetime, not null</tt>
# *updated_at*::  <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
FactoryBot.define do
  factory :marketing_creatives_category_info, class: MarketingCreatives::CategoryInfo do
    description { generate(:random_text) }

    association :profile, factory: :marketing_creatives_profile
    association :category, factory: :marketing_creatives_category

    image { Rack::Test::UploadedFile.new(Rails.root.join("test", "test.png"), "image/png") }

    transient do
      picture_count { rand(3) }
    end

    after(:create) do |category_info, evaluator|
      create_list(:picture, evaluator.picture_count, gallery: category_info)
    end
  end
end
