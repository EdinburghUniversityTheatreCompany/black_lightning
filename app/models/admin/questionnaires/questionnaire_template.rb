##
# A template for the questions that may be used in a questionnaire.
#
# == Schema Information
#
# Table name: admin_questionnaires_questionnaire_templates
#
# *id*::         <tt>integer, not null, primary key</tt>
# *name*::       <tt>string(255)</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
class Admin::Questionnaires::QuestionnaireTemplate < ApplicationRecord
  include ApplicationHelper

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  has_many :questions, as: :questionable
  has_many :notify_emails
  has_many :notify_emails, class_name: "Email", as: :attached_object, dependent: :destroy

  accepts_nested_attributes_for :questions, reject_if: :all_blank, allow_destroy: true
  accepts_nested_attributes_for :notify_emails, reject_if: :all_blank, allow_destroy: true

  normalizes :name, with: ->(name) { name&.strip }

  def as_json(options = {})
    defaults = { include: [ :questions, :notify_emails ] }

    options = merge_hash(defaults, options)

    super(options)
  end

def self.ransackable_attributes(auth_object = nil)
    %w[name]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[questions]
  end
end
