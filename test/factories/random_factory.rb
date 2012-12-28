FactoryGirl.define do
  sequence :random_name do |n|
    "A Name #{n}"
  end

  sequence(:random_text)   {|n|  Faker::Lorem.paragraphs(3).join('\n\n') }
  sequence(:random_string) {|n|  Faker::Lorem.words(5).join(' ') }

  sequence(:random_date) do |n|
    # See http://stackoverflow.com/a/4899857
    from = 2.years.ago
    to   = 2.years.from_now

    Time.at(from + rand * (to.to_f - from.to_f))
  end

  sequence :random_password do |n|
    (0...8).map{65.+(rand(26)).chr}.join
  end
end
