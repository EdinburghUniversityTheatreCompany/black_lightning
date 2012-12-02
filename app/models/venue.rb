# == Schema Information
#
# Table name: venues
#
#  id                 :integer          not null, primary key
#  name               :string(255)
#  tagline            :string(255)
#  description        :text
#  location           :string(255)
#  image_file_name    :string(255)
#  image_content_type :string(255)
#  image_file_size    :integer
#  image_updated_at   :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#

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
