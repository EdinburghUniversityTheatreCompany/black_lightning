# in_time_zone, never Date#to_time: the latter builds a Time in the SYSTEM zone,
# so every occurrence was an hour out under CI's UTC while passing on a
# Europe/London laptop.
FactoryBot.define do
  factory :event_occurrence do
    event
    starts_at { event.start_date.in_time_zone.change(hour: 19, min: 30) }
  end
end
