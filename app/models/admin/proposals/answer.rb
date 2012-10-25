class Admin::Proposals::Answer < ActiveRecord::Base
  belongs_to :question, :class_name => "Admin::Proposals::Question"
  
  attr_accessible :answer
end
