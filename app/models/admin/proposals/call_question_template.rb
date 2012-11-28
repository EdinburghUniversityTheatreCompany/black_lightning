class Admin::Proposals::CallQuestionTemplate < ActiveRecord::Base
  has_many :questions, :as => :questionable

  accepts_nested_attributes_for :questions, :reject_if => :all_blank, :allow_destroy => true

  attr_accessible :name, :questions, :questions_attributes
end
