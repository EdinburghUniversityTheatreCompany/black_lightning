class Season < ActiveRecord::Base
  attr_accessible :description, :end_date, :name, :start_date
  
  has_many :shows
end
