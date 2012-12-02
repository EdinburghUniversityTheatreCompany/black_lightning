##
# Represents a picture in the polymorphic association <tt>gallery</tt>
#
# == Paperclip
# Images are stored as:
# * thumb   (150x100)
# * display (700x700)
#
# == Schema Information
#
# Table name: pictures
#
#  id                 :integer          not null, primary key
#  description        :text
#  gallery_id         :integer
#  gallery_type       :string(255)
#  image_file_name    :string(255)
#  image_content_type :string(255)
#  image_file_size    :integer
#  image_updated_at   :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
##

class Picture < ActiveRecord::Base
  belongs_to :gallery, :polymorphic => true

  has_attached_file :image, :styles => { :thumb => "150x100", :display => "700x700" }

  attr_accessible :description, :image
end
