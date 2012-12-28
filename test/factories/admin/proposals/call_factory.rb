# == Schema Information
#
# Table name: admin_proposals_calls
#
# *id*::         <tt>integer, not null, primary key</tt>
# *deadline*::   <tt>datetime</tt>
# *name*::       <tt>string(255)</tt>
# *open*::       <tt>boolean</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
# *archived*::   <tt>boolean</tt>
#--
# == Schema Information End
#++

FactoryGirl.define do
  factory :proposal_call, class: Admin::Proposals::Call do
    name     { generate(:random_string) }
    open     { [true, false].sample }
    deadline { 5.days.from_now }

    ignore do
      question_count 0
      proposal_count 0
    end

    after(:create) do |call, evaluator|
      FactoryGirl.create_list(:question, evaluator.question_count, questionable: call)
      FactoryGirl.create_list(:proposal, evaluator.proposal_count, call: call)
    end
  end
end
