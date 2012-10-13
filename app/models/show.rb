class Show < ActiveRecord::Base
  resourcify
  def to_param
    slug
  end
  
  validates :slug, :presence => true, :uniqueness => true

  attr_accessible :description, :name, :slug, :tagline, :xts_id
end
