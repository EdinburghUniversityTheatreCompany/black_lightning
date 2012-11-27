class Picture < ActiveRecord::Base
  belongs_to :gallery, :polymorphic => true

  has_attached_file :image, :styles => { :thumb => "x100>", :display => "700>" }

  attr_accessible :description, :image
end
