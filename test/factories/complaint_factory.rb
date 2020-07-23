# == Schema Information
#
# Table name: complaints
#
# *id*::          <tt>bigint, not null, primary key</tt>
# *subject*::     <tt>string(255)</tt>
# *description*:: <tt>text(65535)</tt>
# *resolved*::    <tt>boolean</tt>
# *comments*::    <tt>text(65535)</tt>
# *created_at*::  <tt>datetime, not null</tt>
# *updated_at*::  <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
FactoryBot.define do
  factory :complaint do
    subject { generate(:random_string) }
    description { generate(:random_text) }
    comments { generate(:random_text) }
    resolved { [true, false].sample }
  end
end
