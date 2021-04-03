# == Schema Information
#
# Table name: reviews
#
# *id*::           <tt>integer, not null, primary key</tt>
# *show_id*::      <tt>integer</tt>
# *reviewer*::     <tt>string(255)</tt>
# *body*::         <tt>text(65535)</tt>
# *rating*::       <tt>decimal(2, 1)</tt>
# *review_date*::  <tt>date</tt>
# *created_at*::   <tt>datetime, not null</tt>
# *updated_at*::   <tt>datetime, not null</tt>
# *organisation*:: <tt>string(255)</tt>
#--
# == Schema Information End
#++

FactoryBot.define do
  factory :review do
    reviewer     { Faker::Name.name }
    body         { generate(:random_text) }
    review_date  { generate(:random_date) }
    rating       { Random.rand(0.1..5.0)  }
  end
end
