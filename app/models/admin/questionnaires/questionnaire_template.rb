# == Schema Information
#
# Table name: admin_questionnaires_questionnaire_templates
#
#  id         :integer          not null, primary key
#  name       :integer
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

class Admin::Questionnaires::QuestionnaireTemplate < ActiveRecord::Base
  has_many :questions, :as => :questionable

  accepts_nested_attributes_for :questions, :reject_if => :all_blank, :allow_destroy => true

  attr_accessible :name, :questions, :questions_attributes
end
