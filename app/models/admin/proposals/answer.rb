class Admin::Proposals::Answer < ActiveRecord::Base
  belongs_to :question, :class_name => "Admin::Proposals::Question"
  belongs_to :proposal, :class_name => "Admin::Proposals::Proposal"

  attr_accessible :answer, :question_id
end
