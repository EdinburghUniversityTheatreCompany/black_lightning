class Admin::Proposals::Proposal < ActiveRecord::Base
  belongs_to :call, :class_name => "Admin::Proposals::Call"
  
  has_many :questions, :through => :answers
  has_many :answers, :class_name => "Admin::Proposals::Answer"
  has_many :team_members, :class_name => "::TeamMember", :as => :teamwork
  has_many :users, :through => :team_members
  
  accepts_nested_attributes_for :answers, :team_members
  
  validates :show_title, :proposal_text, :publicity_text, :presence => true
  validates :team_members, :presence => { :message => "You must add at least one team member" }
  
  ################################################################################
  # NOTE                                                                         #
  #                                                                              #
  # If a proposal has the approved attribute set to false, it has been REJECTED. #
  # A proposal still waiting for approval should have approved set to NULL       #
  ################################################################################
  
  attr_accessible :proposal_text, :publicity_text, :show_title, :answers, :answers_attributes, :team_members, :team_members_attributes, :late, :approved, :successful
end
