##
# Represents a collection of Users that have specific positions.
#
# Used by Event, Admin::Proposals::Proposal
#
# == Schema Information
#
# Table name: team_members
#
# *id*::            <tt>integer, not null, primary key</tt>
# *position*::      <tt>string(255)</tt>
# *user_id*::       <tt>integer</tt>
# *teamwork_id*::   <tt>integer</tt>
# *created_at*::    <tt>datetime, not null</tt>
# *updated_at*::    <tt>datetime, not null</tt>
# *teamwork_type*:: <tt>string(255)</tt>
#--
# == Schema Information End
#++
class TeamMember < ActiveRecord::Base
  validates :position, :user, presence: true
  validates_uniqueness_of :user_id, scope: [ :teamwork_type, :teamwork_id ]
  validate :uniqueness_in_parent_collection

  # It should not be optional, but otherwise this fails on creation when immediately attaching team members.
  # A little bit annoying, definitely.
  belongs_to :teamwork, polymorphic: true, optional: true
  belongs_to :user

  delegate :name, to: :user, prefix: true

  normalizes :position, with: ->(position) { position&.strip }

  default_scope -> { order("position ASC") }

  def self.ransackable_attributes(auth_object = nil)
    %w[position user_id teamwork_id teamwork_type]
  end

  private

  def uniqueness_in_parent_collection
    return unless teamwork && user_id
    return if teamwork.new_record?
    return if teamwork.respond_to?(:type_changed?) && teamwork.type_changed?

    # Access the association's internal target without loading from database
    # This should avoid corrupting the association cache
    collection = teamwork.association(:team_members).target
    my_index = collection.index(self)

    duplicates = collection.each_with_index.select do |tm, idx|
      tm != self && # Not the same object
      tm.user_id == user_id && # Same user
      !tm.marked_for_destruction? && # Not being deleted
      (tm.persisted? || idx < my_index) # Either saved OR appears earlier in collection
    end

    if duplicates.any?
      errors.add(:user_id, "is already a team member on this #{teamwork_type.underscore.humanize.downcase}")
    end
  end
end
