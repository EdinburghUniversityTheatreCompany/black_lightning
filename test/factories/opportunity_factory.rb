FactoryGirl.define do
  factory :opportunity do
     title        { generate(:random_string) }
     description  { generate(:random_text) }
     show_email   { [true, false].sample }
     expiry_date  { 5.days.from_now }

     association :creator, factory: :user
  end
end
