# == Schema Information
#
# Table name: admin_proposals_calls
#
# *id*::                  <tt>integer, not null, primary key</tt>
# *submission_deadline*:: <tt>datetime</tt>
# *name*::                <tt>string(255)</tt>
# *created_at*::          <tt>datetime, not null</tt>
# *updated_at*::          <tt>datetime, not null</tt>
# *archived*::            <tt>boolean</tt>
# *editing_deadline*::    <tt>datetime</tt>
#--
# == Schema Information End
#++

FactoryBot.define do
  factory :proposal_call, class: Admin::Proposals::Call do
    name { generate(:random_string) }

    submission_deadline { 5.days.from_now }
    editing_deadline { submission_deadline.advance(days: 5) }

    transient do
      question_count { 5 }
      proposal_count { 2 }
    end

    after(:create) do |call, evaluator|
      call.questions = FactoryBot.create_list(:question, evaluator.question_count, questionable: call)
      call.proposals = FactoryBot.create_list(:proposal, evaluator.proposal_count, call: call)
      call.save
    end
  end
end
