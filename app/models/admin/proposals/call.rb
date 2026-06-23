##
# Represents a collection of proposals.
#
# == Schema Information
#
# Table name: admin_proposals_calls
# Database name: primary
#
#  id                  :integer          not null, primary key
#  archived            :boolean
#  editing_deadline    :datetime
#  name                :string(255)
#  submission_deadline :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
# Indexes
#
#  index_admin_proposals_calls_on_archived             (archived)
#  index_admin_proposals_calls_on_editing_deadline     (editing_deadline)
#  index_admin_proposals_calls_on_submission_deadline  (submission_deadline)
#
class Admin::Proposals::Call < ApplicationRecord
  validates :submission_deadline, :editing_deadline, :name, presence: true

  has_paper_trail

  # Should stay above the dependent: :destroy clause
  before_destroy :check_if_call_has_proposals
  after_save :instantiate_answers_on_proposals

  has_many :questions, as: :questionable, dependent: :destroy
  has_many :proposals, class_name: "Admin::Proposals::Proposal"

  accepts_nested_attributes_for :questions, reject_if: :all_blank, allow_destroy: true

  normalizes :name, with: ->(name) { name&.strip }

  scope :open, -> { where(submission_deadline: DateTime.current..DateTime::Infinity.new) }
  scope :not_archived, -> { where(archived: [ false, nil ]) }

  def self.ransackable_attributes(auth_object = nil)
    %w[archived editing_deadline name submission_deadline]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[proposals questions versions]
  end

  def open?
    submission_deadline > DateTime.current
  end

  ##
  # Archives a call, if the editing deadline has been reached.
  ##
  def archive
    return false if DateTime.current < editing_deadline

    self.archived = true
    save
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
