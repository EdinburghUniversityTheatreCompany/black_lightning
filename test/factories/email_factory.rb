FactoryBot.define do
  factory :email do
    email { Faker::Internet.email }
    association :attached_object, factory: :questionnaire
  end
end
