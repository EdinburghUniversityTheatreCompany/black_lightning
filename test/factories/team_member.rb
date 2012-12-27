FactoryGirl.define do
  factory :team_member do
    position { ['Director', 'Producer', 'Technical Manager', 'Stage Manager', 'Assistant to Mr B. Hussey'].sample }
    user
  end
end