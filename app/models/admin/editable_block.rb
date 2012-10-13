class Admin::EditableBlock < ActiveRecord::Base
  resourcify
  
  validates :name, :presence => true, :uniqueness => true
  
  attr_accessible :content, :name
end
