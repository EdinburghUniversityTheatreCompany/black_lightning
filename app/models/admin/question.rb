# == Schema Information
#
# Table name: admin_questions
#
#  id                :integer          not null, primary key
#  question_text     :text
#  response_type     :string(255)
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  questionable_id   :integer
#  questionable_type :string(255)
#

class Admin::Question < ActiveRecord::Base
  belongs_to :questionable, :polymorphic => true

  has_many :answers, :class_name => "Admin::Answer", :dependent => :destroy

  validates :question_text, :presence => true

  attr_accessible :question_text, :response_type

  def self.response_types
    ['Short Text', 'Long Text', 'Number', 'Yes/No', 'File']
  end
end
