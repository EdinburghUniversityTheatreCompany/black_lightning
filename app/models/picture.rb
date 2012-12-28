# == Schema Information
#
# Table name: pictures
#
# *id*::                 <tt>integer, not null, primary key</tt>
# *description*::        <tt>text</tt>
# *gallery_id*::         <tt>integer</tt>
# *gallery_type*::       <tt>string(255)</tt>
# *image_file_name*::    <tt>string(255)</tt>
# *image_content_type*:: <tt>string(255)</tt>
# *image_file_size*::    <tt>integer</tt>
# *image_updated_at*::   <tt>datetime</tt>
# *created_at*::         <tt>datetime, not null</tt>
# *updated_at*::         <tt>datetime, not null</tt>
#--
# == Schema Information End
#++

##
# Represents a picture in the polymorphic association <tt>gallery</tt>
#
# == Paperclip
# Images are stored as:
# * thumb   (192x100)
# * display (700x700)
#
# == Schema Information
#
# Table name: pictures
#
# *id*::                 <tt>integer, not null, primary key</tt>
# *description*::        <tt>text</tt>
# *gallery_id*::         <tt>integer</tt>
# *gallery_type*::       <tt>string(255)</tt>
# *image_file_name*::    <tt>string(255)</tt>
# *image_content_type*:: <tt>string(255)</tt>
# *image_file_size*::    <tt>integer</tt>
# *image_updated_at*::   <tt>datetime</tt>
# *created_at*::         <tt>datetime, not null</tt>
# *updated_at*::         <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
##
class Picture < ActiveRecord::Base
  belongs_to :gallery, :polymorphic => true

  has_attached_file :image, :styles => { :thumb => "192x100#", :display => "700x700" }

  attr_accessible :description, :image
end
