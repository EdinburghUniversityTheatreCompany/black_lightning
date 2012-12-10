# == Schema Information
#
# Table name: admin_proposals_call_question_templates
#
# *id*::         <tt>integer, not null, primary key</tt>
# *name*::       <tt>string(255)</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
#--
# == Schema Information End
#++

class Admin::Proposals::CallQuestionTemplate < ActiveRecord::Base
  has_many :questions, :as => :questionable

  accepts_nested_attributes_for :questions, :reject_if => :all_blank, :allow_destroy => true

  attr_accessible :name, :questions, :questions_attributes
end
