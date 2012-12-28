# == Schema Information
#
# Table name: admin_questionnaires_questionnaires
#
# *id*::         <tt>integer, not null, primary key</tt>
# *show_id*::    <tt>integer</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
# *name*::       <tt>string(255)</tt>
#--
# == Schema Information End
#++

##
# Represents a Questionnaire that must be answered by a Show's team.
#
# == Schema Information
#
# Table name: admin_questionnaires_questionnaires
#
# *id*::         <tt>integer, not null, primary key</tt>
# *show_id*::    <tt>integer</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
# *name*::       <tt>string(255)</tt>
#--
# == Schema Information End
#++
##
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
