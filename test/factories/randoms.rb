FactoryGirl.define do
  sequence :random_name do |n|
    "A Name #{n}"
  end

  sequence(:random_string) {|n| LoremIpsum.generate }
end
