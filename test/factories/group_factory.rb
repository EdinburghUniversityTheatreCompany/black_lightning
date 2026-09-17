FactoryBot.define do
factory :group, class: Group do
        name { generate :random_string }
    end
end
