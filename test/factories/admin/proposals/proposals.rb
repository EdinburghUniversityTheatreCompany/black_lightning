FactoryGirl.define do
  factory :proposal, class: Admin::Proposals::Proposal do
    show_title     { generate(:random_string) }
    proposal_text  { generate(:random_text) }
    publicity_text { generate(:random_text) }
    approved       { [true, nil, false].sample }

    after(:build) do |proposal, evaluator|
      proposal.team_members << FactoryGirl.build_list(:team_member, 5, teamwork: proposal)
    end

    after(:create) do |proposal, evaluator|
      proposal.call.questions.each do |q|
        create(:answer, question: q, answerable: proposal)
      end
    end
  end
end