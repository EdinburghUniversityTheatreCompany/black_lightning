# == Schema Information
#
# Table name: news
#
# *id*::                 <tt>integer, not null, primary key</tt>
# *title*::              <tt>string(255)</tt>
# *body*::               <tt>text</tt>
# *slug*::               <tt>string(255)</tt>
# *publish_date*::       <tt>datetime</tt>
# *show_public*::        <tt>boolean</tt>
# *created_at*::         <tt>datetime, not null</tt>
# *updated_at*::         <tt>datetime, not null</tt>
# *image_file_name*::    <tt>string(255)</tt>
# *image_content_type*:: <tt>string(255)</tt>
# *image_file_size*::    <tt>integer</tt>
# *image_updated_at*::   <tt>datetime</tt>
# *author_id*::          <tt>integer</tt>
#--
# == Schema Information End
#++

##
# Nothing really interesting about news. It's news.
#
# == Paperclip
# Images are stored as:
# * medium (576x300)
# * thumb  (192x100)
#
# == Schema Information
#
# Table name: news
#
# *id*::                 <tt>integer, not null, primary key</tt>
# *title*::              <tt>string(255)</tt>
# *body*::               <tt>text</tt>
# *slug*::               <tt>string(255)</tt>
# *publish_date*::       <tt>datetime</tt>
# *show_public*::        <tt>boolean</tt>
# *created_at*::         <tt>datetime, not null</tt>
# *updated_at*::         <tt>datetime, not null</tt>
# *image_file_name*::    <tt>string(255)</tt>
# *image_content_type*:: <tt>string(255)</tt>
# *image_file_size*::    <tt>integer</tt>
# *image_updated_at*::   <tt>datetime</tt>
# *author_id*::          <tt>integer</tt>
#--
# == Schema Information End
#++
##
class News < ActiveRecord::Base
  resourcify

  ##
  # Use the format id-slug for urls. e.g. /news/1-mynews
  ##
  def to_param
    "#{id}-#{slug}"
  end

  belongs_to :author, :class_name => "User"

  validates :title, :presence => true
  validates :publish_date, :presence => true
  validates :slug, :presence => true, :uniqueness => true

  scope :current, where(["publish_date <= ?", Time.current]).order("publish_date DESC")
  scope :public, where(["publish_date <= ? AND show_public = ?", Time.current, true]).order("publish_date DESC")

  has_attached_file :image, :styles => { :medium => "576x300#", :thumb => "192x100#" }
  attr_accessible :publish_date, :show_public, :slug, :title, :body, :image
end
