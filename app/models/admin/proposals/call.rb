##
# Represents a collection of proposals.
#
# == Schema Information
#
# Table name: admin_proposals_calls
#
# *id*::         <tt>integer, not null, primary key</tt>
# *deadline*::   <tt>datetime</tt>
# *name*::       <tt>string(255)</tt>
# *open*::       <tt>boolean</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
# *archived*::   <tt>boolean</tt>
#--
# == Schema Information End
#++
##
class Admin::Proposals::Call < ActiveRecord::Base
  has_many :questions, as: :questionable, dependent: :destroy
  has_many :proposals, class_name: 'Admin::Proposals::Proposal'

  scope :open, -> { where(open: true) }

  accepts_nested_attributes_for :questions, reject_if: :all_blank, allow_destroy: true

  validates :deadline, :name, presence: true

  attr_accessible :deadline, :name, :open, :archived, :questions, :questions_attributes

  before_update :mark_non_members_as_late, :if => :open_changed?

  ##
  # Closes the call, and archives it.
  ##
  def archive
    self.open = false

    self.archived = true

    self.save!
  end

  def mark_non_members_as_late
    return if self.open
    self.proposals.each do |proposal|
      if proposal.has_non_members
        proposal.late = true
        proposal.save
      end
    end
  end

end
