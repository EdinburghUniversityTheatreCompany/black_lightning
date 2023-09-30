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

  default_scope -> { order('position ASC') }

  # It should not be optional, but otherwise this fails on creation when immediately attaching team members.
  # A little bit annoying, definitely.
  belongs_to :teamwork, polymorphic: true, optional: true
  belongs_to :user

  delegate :name, to: :user, prefix: true

  def self.ransackable_attributes(auth_object = nil)
    %w[position user_id teamwork_id teamwork_type]
  end
end
