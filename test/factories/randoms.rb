FactoryGirl.define do
  sequence :random_name do |n|
    "A Name #{n}"
  end

  sequence(:random_text) {|n|  Lorem::Base.new(:paragraphs, 3).output() }
  sequence(:random_string) {|n|  Lorem::Base.new(:words, 5).output() }
end
