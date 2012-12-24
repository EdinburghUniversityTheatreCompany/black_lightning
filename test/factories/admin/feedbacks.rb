FactoryGirl.define do
  factory :feedback, class: Admin::Feedback do
    body  :random_string
    show
  end
end