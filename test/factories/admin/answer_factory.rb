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
    end

    answer do
      case response_type
        when 'Short Text'
          generate(:random_string)
        when 'Long Text'
          generate(:random_text)
        when 'Number'
          Random.new.rand(500)
        when 'Yes/No'
          %w(Yes No).sample
        when 'File'
      end
    end

    file { Rack::Test::UploadedFile.new(Rails.root.join('test', 'test.pdf'), 'application/pdf') if response_type.downcase == 'file' }
    
    answerable { question.questionable }
  end
end
