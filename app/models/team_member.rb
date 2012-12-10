##
# Represents a collection of Users that have specific positions.
#
# Used by Show, Admin::Proposals::Proposal
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
##
class TeamMember < ActiveRecord::Base
  belongs_to :teamwork, :polymorphic => true
  belongs_to :user

  validates :position, :presence => true

  attr_accessible :position, :user, :user_id, :proposal, :proposal_id
end
