# == Schema Information
#
# Table name: marketing_creatives_profiles
#
# *id*::         <tt>bigint, not null, primary key</tt>
# *name*::       <tt>string(255)</tt>
# *url*::        <tt>string(255)</tt>
# *about*::      <tt>text(65535)</tt>
# *approved*::   <tt>boolean</tt>
# *user_id*::    <tt>integer</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
FactoryBot.define do
  factory :marketing_creatives_profile, class: MarketingCreatives::Profile do
    name { generate(:random_string) }
    url { name.to_url }
    about { generate(:random_text) }
    contact { generate(:random_text) }

    approved { [ true, false ].sample }

    transient do
      attach_user { [ true, false ].sample }
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
