# == Schema Information
#
# Table name: admin_answers
#
#  id              :integer          not null, primary key
#  question_id     :integer
#  answerable_id   :integer
#  answer          :text
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  answerable_type :string(255)
#

class Admin::Answer < ActiveRecord::Base
  belongs_to :question, :class_name => "Admin::Question"
  belongs_to :answerable, :polymorphic => true

  attr_accessible :answer, :question_id
end
