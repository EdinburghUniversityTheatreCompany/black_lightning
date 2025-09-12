FactoryBot.define do
  factory :fault_report, class: FaultReport do
    item { generate(:random_string) }
    description { generate(:random_string) }
    severity { %I[annoying probably_worth_fixing show_impeding dangerous].sample }
    status { %I[reported in_progress cant_fix wont_fix on_hold completed].sample }

    association :reported_by, factory: :user
  end
end
