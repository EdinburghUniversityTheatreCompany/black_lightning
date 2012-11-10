class Admin::Proposals::Call < ActiveRecord::Base
  scope :open, :conditions => { :open => true }

  has_and_belongs_to_many :questions, :class_name => "Admin::Proposals::Question"
  
  has_many :proposals, :class_name => "Admin::Proposals::Proposal"
  
  accepts_nested_attributes_for :questions, :reject_if => :all_blank, :allow_destroy => true
  
  validates :deadline, :name, :presence => true
  
  attr_accessible :deadline, :name, :open, :questions, :questions_attributes
end
