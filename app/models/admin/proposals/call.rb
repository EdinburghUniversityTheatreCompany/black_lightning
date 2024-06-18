##
# Represents a collection of proposals.
#
# == Schema Information
#
# Table name: admin_proposals_calls
#
# *id*::                  <tt>integer, not null, primary key</tt>
# *submission_deadline*:: <tt>datetime</tt>
# *name*::                <tt>string(255)</tt>
# *created_at*::          <tt>datetime, not null</tt>
# *updated_at*::          <tt>datetime, not null</tt>
# *archived*::            <tt>boolean</tt>
# *editing_deadline*::    <tt>datetime</tt>
#--
# == Schema Information End
#++
class Admin::Proposals::Call < ApplicationRecord
  validates :submission_deadline, :editing_deadline, :name, presence: true

  has_paper_trail

  # Should stay above the dependent: :destroy clause
  before_destroy :check_if_call_has_proposals
  after_save :instantiate_answers_on_proposals

  has_many :questions, as: :questionable, dependent: :destroy
  has_many :proposals, class_name: 'Admin::Proposals::Proposal'

  accepts_nested_attributes_for :questions, reject_if: :all_blank, allow_destroy: true

  normalizes :name, with: -> (name) { name&.strip }

  # TODO: Maybe revise what open means?
  scope :open, -> { where(submission_deadline: DateTime.now..DateTime::Infinity.new) }

  def self.ransackable_attributes(auth_object = nil)
    %w[archived editing_deadline name submission_deadline]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[proposals questions versions]
  end

  def open?
    return submission_deadline > DateTime.now
  end

  ##
  # Archives a call, if the editing deadline has been reached.
  ##
  def archive
    return false if DateTime.now < editing_deadline

    self.archived = true
    return save
  end

  private

  def check_if_call_has_proposals
    return if proposals.empty?

    errors.add(:destroy, "You cannot destroy the call because there are proposals attached to it.#{' Archive the call instead.' unless archived}")
    throw(:abort)
  end

  def instantiate_answers_on_proposals
    proposals.each(&:instantiate_answers!)
  end
end
