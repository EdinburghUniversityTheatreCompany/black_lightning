class Show < ActiveRecord::Base
  resourcify
  def to_param
    slug
  end
  
  validates :name, :description, :presence => true
  validates :slug, :presence => true, :uniqueness => true

  has_attached_file :image, :styles => { :medium => "x300>", :thumb => "x100>", :slideshow => "960x500#" }
  attr_accessible :description, :name, :slug, :tagline, :xts_id, :is_public, :image, :start_date, :end_date
end
