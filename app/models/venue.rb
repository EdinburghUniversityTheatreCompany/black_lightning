# == Schema Information
#
# Table name: venues
#
# *id*::                 <tt>integer, not null, primary key</tt>
# *name*::               <tt>string(255)</tt>
# *tagline*::            <tt>string(255)</tt>
# *description*::        <tt>text</tt>
# *location*::           <tt>string(255)</tt>
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
# Represents a venue.
#
# Note that while urls are generated to include the slug, like Show, they also include the id.
#
# Therefore, unlike Show, it is NOT necessary to search for the venue by slug - using <tt>find</tt> will work perfectly well.
#
# == Paperclip
# Images are stored as:
# * thumb:     (192x100)
# * slideshow: (960x500)
#
# == Schema Information
#
# Table name: venues
#
# *id*::                 <tt>integer, not null, primary key</tt>
# *name*::               <tt>string(255)</tt>
# *tagline*::            <tt>string(255)</tt>
# *description*::        <tt>text</tt>
# *location*::           <tt>string(255)</tt>
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
class Venue < ActiveRecord::Base
  def to_param
    "#{id}-#{name.gsub(/\s+/,'-').gsub(/[^a-zA-Z0-9\-]/,'').downcase.gsub(/\-{2,}/,'-')}"
  end

  has_many :shows
  has_many :pictures, :as => :gallery

  has_attached_file :image, :styles => { :thumb => "192x100#", :slideshow => "960x500#" }

  accepts_nested_attributes_for :pictures, :reject_if => :all_blank, :allow_destroy => true

  attr_accessible :description, :image, :location, :name, :tagline
end
