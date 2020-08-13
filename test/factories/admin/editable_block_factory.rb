# == Schema Information
#
# Table name: admin_editable_blocks
#
# *id*::         <tt>integer, not null, primary key</tt>
# *name*::       <tt>string(255)</tt>
# *content*::    <tt>text(65535)</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
# *admin_page*:: <tt>boolean</tt>
# *group*::      <tt>string(255)</tt>
#--
# == Schema Information End
#++
FactoryBot.define do
  factory :editable_block, class: Admin::EditableBlock do
    name { generate :random_string }
    url { name.to_url }

    content { generate :random_string }
    group { generate :random_string }
  end
end
