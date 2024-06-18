##
# A template for the questions that may be used in a proposal call.
#
# == Schema Information
#
# Table name: admin_proposals_call_question_templates
#
# *id*::         <tt>integer, not null, primary key</tt>
# *name*::       <tt>string(255)</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
class Admin::Proposals::CallQuestionTemplate < ApplicationRecord
  include ApplicationHelper

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  has_many :questions, as: :questionable
  accepts_nested_attributes_for :questions, reject_if: :all_blank, allow_destroy: true

  normalizes :name, with: -> (name) { name&.strip }

  def as_json(options = {})
    defaults = { include: [:questions] }

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
