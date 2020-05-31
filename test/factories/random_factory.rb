FactoryBot.define do
  sequence :random_name do |n|
    "A Name #{n}"
  end

  sequence(:random_text)   { |_n|  Faker::Lorem.paragraphs(number: 3).join('\n\n') }
  sequence(:random_string) { |_n|  Faker::Lorem.words(number: 5).join(' ') }

  sequence(:random_date) do |_n|
    # See http://stackoverflow.com/a/4899857
    from = 2.years.ago
    to   = 2.years.from_now

    Time.at(from + rand * (to.to_f - from.to_f))
  end

  sequence(:random_past_date) do |_n|
    # See http://stackoverflow.com/a/4899857
    from = 2.years.ago
    to   = Time.now - 1.day

    Time.at(from + rand * (to.to_f - from.to_f))
  end

  sequence(:random_future_date) do |_n|
    # See http://stackoverflow.com/a/4899857
    from = Time.now + 1.day
    to   = 2.years.from_now

    Time.at(from + rand * (to.to_f - from.to_f))
  end

  sequence :random_password do |_n|
    (0...8).map { 65.+(rand(26)).chr }.join
  end
end
