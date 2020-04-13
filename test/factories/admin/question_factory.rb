# == Schema Information
#
# Table name: admin_questions
#
# *id*::                <tt>integer, not null, primary key</tt>
# *question_text*::     <tt>text</tt>
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
    question_text { :random_text }
    response_type { ['Short Text', 'Long Text', 'Number', 'Yes/No', 'File'].sample }

    transient do
      answered   { [true, false].sample }
      answerable { nil }
    end

    after(:create) do |question, evaluator|
      if evaluator.answered
        FactoryBot.create(:answer, question_id: question.id, response_type: question.response_type, answerable: evaluator.answerable)
      end
    end
  end
end
