FactoryGirl.define do
  factory :questionnaire, class: Admin::Questionnaires::Questionnaire do
    name  { generate(:random_name) }
    show
  end
end