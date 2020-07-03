FactoryBot.define do
  factory :editable_block, class: Admin::EditableBlock do
    name { generate :random_string }
    content { generate :random_string }
    group { generate :random_string }
  end
end
