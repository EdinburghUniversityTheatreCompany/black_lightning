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

    transient do
      event_team_member_count { 0 }
    end

    before(:create) do |questionnaire, evaluator|
      questionnaire.event = FactoryBot.create(%i[show workshop season].sample, team_member_count: evaluator.event_team_member_count) unless questionnaire.event.present?
    end

    after(:create) do |questionnaire, _evaluator|
      questions = FactoryBot.create_list(:question, 5, questionable: questionnaire)
      emails = FactoryBot.create_list(:email, 2, attached_object: questionnaire)
    end

    trait :with_team_members do
      event_team_member_count { 1 }
    end
  end
end
