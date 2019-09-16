##
# A template for the questions that may be used in a questionnaire.
#
# == Schema Information
#
# Table name: admin_questionnaires_questionnaire_templates
#
# *id*::         <tt>integer, not null, primary key</tt>
# *name*::       <tt>string(255)</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
##
class Admin::Questionnaires::QuestionnaireTemplate < ActiveRecord::Base
  has_many :questions, as: :questionable

  accepts_nested_attributes_for :questions, reject_if: :all_blank, allow_destroy: true
end
