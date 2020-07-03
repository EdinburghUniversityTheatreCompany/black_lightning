# == Schema Information
#
# Table name: admin_questionnaires_questionnaires
#
# *id*::         <tt>integer, not null, primary key</tt>
# *event_id*::   <tt>integer</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
# *name*::       <tt>string(255)</tt>
#--
# == Schema Information End
#++

FactoryBot.define do
  factory :questionnaire, class: Admin::Questionnaires::Questionnaire do
    name  { generate(:random_name) }

    before(:create) do |questionnaire, _evaluator|
      questionnaire.event = FactoryBot.create(%i[show workshop season].sample) unless questionnaire.event.present?
    end

    after(:create) do |questionnaire, _evaluator|
      questions = FactoryBot.create_list(:question, 10, questionable: questionnaire)
    end
  end
end
