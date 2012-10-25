class Admin::Proposals::Call < ActiveRecord::Base
  has_and_belongs_to_many :questions, :class_name => "Admin::Proposals::Question"
  
  has_many :proposals, :class_name => "Admin::Proposals::Proposal"
  
  accepts_nested_attributes_for :questions
  attr_accessible :deadline, :name, :open, :questions
end
