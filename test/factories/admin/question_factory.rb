# == Schema Information
#
# Table name: admin_questions
#
# *id*::                <tt>integer, not null, primary key</tt>
# *question_text*::     <tt>text(65535)</tt>
# *response_type*::     <tt>string(255)</tt>
# *created_at*::        <tt>datetime, not null</tt>
# *updated_at*::        <tt>datetime, not null</tt>
# *questionable_id*::   <tt>integer</tt>
# *questionable_type*:: <tt>string(255)</tt>
#--
# == Schema Information End
#++

FactoryBot.define do
  factory :question, class: Admin::Question do
    association :questionable, factory: :questionnaire

    question_text { generate(:random_text) }
    response_type { ['Short Text', 'Long Text', 'Number', 'Yes/No', 'File'].sample }

    transient do
      answered { [true, false].sample }
    end

    after(:create) do |question, evaluator|
      if evaluator.answered && question.answers.empty?
        FactoryBot.create(:answer, question_id: question.id, response_type: question.response_type, answerable: question.questionable)
      end
    end
  end
end
