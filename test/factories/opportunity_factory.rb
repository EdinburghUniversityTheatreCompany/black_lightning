FactoryGirl.define do
  factory :opportunity do
     title        { generate(:random_string) }
     description  { generate(:random_text) }
     show_email   { [true, false].sample }
     association :creator, factory: :user
  end
end
