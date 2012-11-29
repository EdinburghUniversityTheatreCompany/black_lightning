class Picture < ActiveRecord::Base
  belongs_to :gallery, :polymorphic => true

  has_attached_file :image, :styles => { :thumb => "150>", :display => "700>" }

  attr_accessible :description, :image
end
