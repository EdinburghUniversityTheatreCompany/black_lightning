class Season < ActiveRecord::Base
  def to_param
    slug
  end
  attr_accessible :description, :end_date, :name, :start_date, :slug
  
  validates :slug, :presence => true, :uniqueness => true
  
  has_many :shows
  
  
end
