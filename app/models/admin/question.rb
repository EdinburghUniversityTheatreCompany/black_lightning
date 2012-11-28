class Admin::Question < ActiveRecord::Base
  belongs_to :questionable, :polymorphic => true

  has_many :answers, :class_name => "Admin::Answer", :dependent => :destroy

  validates :question_text, :presence => true

  attr_accessible :question_text, :response_type
end
