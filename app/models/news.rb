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

  belongs_to :author, class_name: 'User'

  validates :title, presence: true
  validates :publish_date, presence: true
  validates :slug, presence: true, uniqueness: true

  # News should always be ordered by publish_date DESC
  default_scope -> { order('publish_date DESC') }

  scope :current, -> { where(['publish_date <= ?', Time.current]) }
  scope :for_public, -> { where(['publish_date <= ? AND show_public = ?', Time.current, true]) }

  has_attached_file :image,
                    styles: { medium: '576x300#', thumb: '192x100#' },
                    convert_options: { medium: '-strip', thumb: '-quality 75 -strip' },
                    default_url: :default_image

  attr_accessible :publish_date, :show_public, :slug, :title, :body, :image

  ##
  # Generates a default image for the news item. If extra artwork is added, increase the base of the modulo call.
  #
  # NOTE: The first image must have filename 0.png - remember that in modulo 2 (for example), valid numbers are 0,1 (not 2)!
  ##
  def default_image
    number = id.modulo(2)
    return "/images/generic_news/:style/#{number}.png"
  end
end
