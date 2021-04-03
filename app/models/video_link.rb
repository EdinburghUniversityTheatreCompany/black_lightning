# == Schema Information
#
# Table name: video_links
#
# *id*::           <tt>bigint, not null, primary key</tt>
# *name*::         <tt>string(255), not null</tt>
# *link*::         <tt>string(255), not null</tt>
# *access_level*:: <tt>integer, default(1), not null</tt>
# *order*::        <tt>integer</tt>
# *item_type*::    <tt>string(255)</tt>
# *item_id*::      <tt>bigint</tt>
# *created_at*::   <tt>datetime, not null</tt>
# *updated_at*::   <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
class VideoLink < ApplicationRecord
  belongs_to :item, polymorphic: true

  validate :link_is_valid
  validates :name, :link, :access_level, presence: true

  default_scope -> { order(order: :asc) }

  # They're the same, so why not?
  ACCESS_LEVELS = Attachment::ACCESS_LEVELS

  VIDEO_EMBED_WIDTH = 560
  VIDEO_EMBED_HEIGHT = 315

  YOUTUBE_ID_REGEX = %r/^.*(?:(?:youtu\.be\/|v\/|vi\/|u\/\w\/|embed\/)|(?:(?:watch)?\?v(?:i)?=|\&v(?:i)?=))([^#\&\?]*).*/

  def youtube_video_id
    id = YOUTUBE_ID_REGEX.match(link)

    return id[1] if id.present?
  end

  def embed_code
    id = youtube_video_id

    return 'The video link is not valid.' if id.nil?

    return "<iframe width=\"#{VIDEO_EMBED_WIDTH}\" height=\"#{VIDEO_EMBED_HEIGHT}\" src=\"https://www.youtube-nocookie.com/embed/#{id}\" frameborder=\"0\" allow=\"autoplay; encrypted-media\" allowfullscreen></iframe>".html_safe
  end

  def link_is_valid
    errors.add(:link, 'is not a valid YouTube link') if youtube_video_id.nil?
  end
end
