FactoryBot.define do
  factory :opportunity do
    title        { generate(:random_string) }
    description  { generate(:random_text) }
    show_email   { [true, false].sample }
    expiry_date  { [-1.days.from_now, 1.days.from_now].sample }
    approved     { [true, false].sample }

    association :creator, factory: :user
  end
end
