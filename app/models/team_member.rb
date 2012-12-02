# == Schema Information
#
# Table name: team_members
#
#  id            :integer          not null, primary key
#  position      :string(255)
#  user_id       :integer
#  teamwork_id   :integer
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  teamwork_type :string(255)
#

class TeamMember < ActiveRecord::Base
  belongs_to :teamwork, :polymorphic => true
  belongs_to :user

  validates :position, :presence => true

  attr_accessible :position, :user, :user_id, :proposal, :proposal_id
end
