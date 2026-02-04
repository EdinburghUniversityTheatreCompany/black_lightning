# == Schema Information
#
# Table name: admin_answers
#
# *id*::                <tt>integer, not null, primary key</tt>
# *question_id*::       <tt>integer</tt>
# *answerable_id*::     <tt>integer</tt>
# *answer*::            <tt>text(65535)</tt>
# *created_at*::        <tt>datetime, not null</tt>
# *updated_at*::        <tt>datetime, not null</tt>
# *answerable_type*::   <tt>string(255)</tt>
# *file_file_name*::    <tt>string(255)</tt>
# *file_content_type*:: <tt>string(255)</tt>
# *file_file_size*::    <tt>integer</tt>
# *file_updated_at*::   <tt>datetime</tt>
#--
# == Schema Information End
#++

FactoryBot.define do
  factory :answer, class: Admin::Answer do
    question

    transient do
      response_type { question.response_type }
      with_attachment { false }
    end

    answer do
      case response_type
      when "Short Text"
          generate(:random_string)
      when "Long Text"
          generate(:random_text)
      when "Number"
          Random.new.rand(500)
      when "Yes/No"
          %w[Yes No].sample
      when "File"
      end
    end

    answerable { question.questionable }

    after(:create) do |answer, evaluator|
      if evaluator.response_type.present?
        answer.question.update(response_type: evaluator.response_type)

        FactoryBot.create(:attachment, item: answer) if evaluator.with_attachment && answer.attachments.empty?
      end
    end

    trait :with_attachment do
      with_attachment { true }
    end
  end
end
