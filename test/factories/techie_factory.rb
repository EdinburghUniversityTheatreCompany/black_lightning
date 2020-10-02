# == Schema Information
#
# Table name: techies
#
# *id*::         <tt>integer, not null, primary key</tt>
# *name*::       <tt>string(255)</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
#--
# == Schema Information End
#++

FactoryBot.define do
  factory :techie do
    name { generate(:random_name) }

    transient do
      amount_of_parents { 1 }
      amount_of_children { 0 }
    end

    after(:create) do |techie, evaluator|
      (0..evaluator.amount_of_parents).each do
        techie.parents << Techie.all.sample
      end

      (0..evaluator.amount_of_children).each do
        techie.children << Techie.all.sample
      end
    end
  end
end
