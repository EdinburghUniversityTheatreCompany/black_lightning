##
# Represents a Questionnaire that must be answered by a Show's team.
#
# == Schema Information
#
# Table name: admin_questionnaires_questionnaires
#
# *id*::         <tt>integer, not null, primary key</tt>
# *event_id*::   <tt>integer</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
# *name*::       <tt>string(255)</tt>
#--
# == Schema Information End
#++
class Admin::Questionnaires::Questionnaire < ApplicationRecord
  validates :event, :name, presence: true

  belongs_to :event

  has_many :questions, as: :questionable, dependent: :destroy
  has_many :answers, as: :answerable
  has_many :team_members, through: :event
  has_many :users, through: :team_members
  has_many :notify_emails, class_name: 'Email', as: :attached_object, dependent: :destroy

  accepts_nested_attributes_for :questions, reject_if: :all_blank, allow_destroy: true
  accepts_nested_attributes_for :answers, reject_if: :all_blank, allow_destroy: true
  accepts_nested_attributes_for :notify_emails, reject_if: :all_blank, allow_destroy: true

  normalizes :name, with: -> (name) { name&.strip }

  def self.ransackable_attributes(auth_object = nil)
    %w[name]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[event]
  end

  def instantiate_answers!
    questions.each do |question|
      next if question.answers.where(answerable: self).any?

      answer = Admin::Answer.new
      answer.question = question
      answers.push(answer)
    end
  end
end
