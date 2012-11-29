class Venue < ActiveRecord::Base
  def to_param
    "#{id}-#{name.gsub(/\s+/,'-').gsub(/[^a-zA-Z0-9\-]/,'').downcase.gsub(/\-{2,}/,'-')}"
  end

  has_many :shows
  has_many :pictures, :as => :gallery

  has_attached_file :image, :styles => { :thumb => "150x100", :slideshow => "960x500#" }

  accepts_nested_attributes_for :pictures, :reject_if => :all_blank, :allow_destroy => true

  attr_accessible :description, :image, :location, :name, :tagline
end
