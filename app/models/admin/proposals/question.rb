class Admin::Proposals::Question < ActiveRecord::Base
  has_many_and_belongs_to :calls, :class_name => "Admin::Proposals::Call"
  
  has_many :answers, :class_name => "Admin::Proposals::Answer"
  
  attr_accessible :question_text
end
