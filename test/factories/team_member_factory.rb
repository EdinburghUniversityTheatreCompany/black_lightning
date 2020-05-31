# == Schema Information
#
# Table name: team_members
#
# *id*::            <tt>integer, not null, primary key</tt>
# *position*::      <tt>string(255)</tt>
# *user_id*::       <tt>integer</tt>
# *teamwork_id*::   <tt>integer</tt>
# *created_at*::    <tt>datetime, not null</tt>
# *updated_at*::    <tt>datetime, not null</tt>
# *teamwork_type*:: <tt>string(255)</tt>
#--
# == Schema Information End
#++

FactoryBot.define do
  factory :team_member do
    position { ['Director', 'Producer', 'Technical Manager', 'Stage Manager', 'Assistant to Mr B. Hussey'].sample }
    # The tests for the call run on the assumption that every team_member of a proposal is a member.
    association :user, factory: :member
  end
end
