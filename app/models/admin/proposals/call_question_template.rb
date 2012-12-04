# == Schema Information
#
# Table name: admin_proposals_call_question_templates
#
#  id         :integer          not null, primary key
#  name       :string(255)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

class Admin::Proposals::CallQuestionTemplate < ActiveRecord::Base
  has_many :questions, :as => :questionable

  accepts_nested_attributes_for :questions, :reject_if => :all_blank, :allow_destroy => true

  attr_accessible :name, :questions, :questions_attributes
end
