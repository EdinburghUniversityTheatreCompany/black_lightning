FactoryGirl.define do
  factory :answer, class: Admin::Answer do
    ignore do
      response_type 'Long Text'
    end

    answer do
      case response_type
        when 'Short Text'
          generate(:random_string)
        when 'Long Text'
          generate(:random_text)
        when 'Number'
          Random.new().rand(500)
        when 'Yes/No'
          ['Yes', 'No'].sample
        when 'File'
      end
    end
  end
end