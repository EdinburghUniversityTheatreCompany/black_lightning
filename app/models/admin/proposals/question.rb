class Admin::Proposals::Question < ActiveRecord::Base
  has_and_belongs_to_many :calls, :class_name => "Admin::Proposals::Call"

  has_many :answers, :class_name => "Admin::Proposals::Answer"

  validates :question_text, :presence => true

  attr_accessible :question_text, :response_type
end
