class Admin::Proposals::CallQuestionTemplate < ActiveRecord::Base
  has_and_belongs_to_many :questions, :class_name => "Admin::Proposals::Question"

  accepts_nested_attributes_for :questions, :reject_if => :all_blank, :allow_destroy => true

  attr_accessible :name, :questions, :questions_attributes
end
