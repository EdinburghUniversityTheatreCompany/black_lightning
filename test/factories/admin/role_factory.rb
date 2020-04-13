FactoryBot.define do
  factory :role, class: Role do
    name { generate :random_string }
  end
end
