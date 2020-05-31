# == Schema Information
#
# Table name: admin_feedbacks
#
# *id*::         <tt>integer, not null, primary key</tt>
# *show_id*::    <tt>integer</tt>
# *body*::       <tt>text</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
#--
# == Schema Information End
#++

FactoryBot.define do
  factory :feedback, class: Admin::Feedback do
    body  { generate :random_string }
    show
  end
end
