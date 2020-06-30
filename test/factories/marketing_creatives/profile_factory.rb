FactoryBot.define do
  factory :marketing_creatives_profile, class: MarketingCreatives::Profile do
    name { generate(:random_string) }
    url { name.to_url }
    about { generate(:random_text) }

    approved { [true, false].sample }

    transient do
      attach_user { [true, false].sample }
      amount_of_category_infos { 1 }
    end

    after(:create) do |profile, evaluator|
      if evaluator.attach_user
        profile.user = FactoryBot.create(:user)
        profile.save
      end

      FactoryBot.create_list(:marketing_creatives_category_info, evaluator.amount_of_category_infos, profile: profile)
    end
  end
end
