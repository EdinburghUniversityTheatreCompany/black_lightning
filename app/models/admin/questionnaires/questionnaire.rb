# == Schema Information
#
# Table name: admin_questionnaires_questionnaires
#
#  id         :integer          not null, primary key
#  show_id    :integer
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

class Admin::Questionnaires::Questionnaire < ActiveRecord::Base

  belongs_to :show

  has_many :questions, :as => :questionable, :dependent => :destroy
  has_many :answers, :as => :answerable
  has_many :team_members, :through => :show
  has_many :users, :through => :team_members

  accepts_nested_attributes_for :questions, :reject_if => :all_blank, :allow_destroy => true
  accepts_nested_attributes_for :answers, :reject_if => :all_blank, :allow_destroy => true

  validates :show_id, :presence => true, :uniqueness => true

  attr_accessible :name, :questions, :questions_attributes, :answers, :answers_attributes

end
