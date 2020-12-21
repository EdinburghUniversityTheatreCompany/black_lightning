# == Schema Information
#
# Table name: attachment_tags
#
# *id*::          <tt>bigint, not null, primary key</tt>
# *name*::        <tt>string(255)</tt>
# *description*:: <tt>text(65535)</tt>
# *created_at*::  <tt>datetime, not null</tt>
# *updated_at*::  <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
FactoryBot.define do
  factory :attachment_tag do
    name { generate(:random_string) }

    description { generate(:random_text) }
  end
end
