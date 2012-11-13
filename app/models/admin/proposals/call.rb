class Admin::Proposals::Call < ActiveRecord::Base
  has_and_belongs_to_many :questions, :class_name => "Admin::Proposals::Question", :before_remove => :answers_cleanup

  has_many :proposals, :class_name => "Admin::Proposals::Proposal"

  accepts_nested_attributes_for :questions, :reject_if => :all_blank, :allow_destroy => true

  validates :deadline, :name, :presence => true

  attr_accessible :deadline, :name, :open, :questions, :questions_attributes
  
  #Removes answers to questions that have been removed
  def answers_cleanup(question)
    self.proposals.each do |proposal|
      proposal.answers.where(:question_id => question.id).destroy_all
    end
  end
end
