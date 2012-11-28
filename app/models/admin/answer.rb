class Admin::Answer < ActiveRecord::Base
  belongs_to :question, :class_name => "Admin::Question"
  belongs_to :answerable, :polymorphic => true

  attr_accessible :answer, :question_id
end
