FactoryGirl.define do
  sequence :random_name do |n|
    "A Name #{n}"
  end

  sequence(:random_text)   {|n|  Faker::Lorem.paragraphs(3).join('\n\n') }
  sequence(:random_string) {|n|  Faker::Lorem.words(5).join(' ') }

  sequence :random_password do |n|
    (0...8).map{65.+(rand(26)).chr}.join
  end
end
