# == Schema Information
#
# Table name: opportunities
#
# *id*::          <tt>integer, not null, primary key</tt>
# *title*::       <tt>string(255)</tt>
# *description*:: <tt>text(65535)</tt>
# *show_email*::  <tt>boolean</tt>
# *approved*::    <tt>boolean</tt>
# *creator_id*::  <tt>integer</tt>
# *approver_id*:: <tt>integer</tt>
# *expiry_date*:: <tt>date</tt>
# *created_at*::  <tt>datetime, not null</tt>
# *updated_at*::  <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
FactoryBot.define do
  factory :opportunity do
    title        { generate(:random_string) }
    description  { generate(:random_text) }
    show_email   { [true, false].sample }
    expiry_date  { [-1.days.from_now, 1.days.from_now].sample }
    approved     { [true, false].sample }

    association :creator, factory: :user
  end
end
