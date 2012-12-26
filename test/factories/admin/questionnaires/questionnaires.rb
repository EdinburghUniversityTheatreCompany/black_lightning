FactoryGirl.define do
  factory :questionnaire, class: Admin::Questionnaires::Questionnaire do
    name  { generate(:random_name) }
    show

    after(:create) do |questionnaire, evaluator|
      questions = FactoryGirl.create_list(:question, 10, questionable: questionnaire, answerable: questionnaire)
    end
  end
end