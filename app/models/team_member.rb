class TeamMember < ActiveRecord::Base
  belongs_to :teamwork, :polymorphic => true
  belongs_to :user

  validates :position, :presence => true

  attr_accessible :position, :user, :user_id, :proposal, :proposal_id
end
