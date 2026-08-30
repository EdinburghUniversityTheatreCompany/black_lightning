FactoryBot.define do
  factory :event_occurrence do
    event
    starts_at { event.start_date.to_time.change(hour: 19, min: 30) }
  end
end
