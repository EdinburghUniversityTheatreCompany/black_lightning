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

  VIDEO_EMBED_WIDTH = 700
  VIDEO_EMBED_HEIGHT = 400

  SHARED_ATTRIBUTES = "width=\"#{VIDEO_EMBED_WIDTH}\" height=\"#{VIDEO_EMBED_HEIGHT}\" frameborder=\"0\" allowfullscreen=\"true\" allow=\"autoplay; clipboard-write; encrypted-media; picture-in-picture; web-share\" class=\"w-100\""

  YOUTUBE_ID_REGEX = %r/^.*(?:(?:youtu\.be\/|v\/|vi\/|u\/\w\/|embed\/)|(?:(?:watch)?\?v(?:i)?=|\&v(?:i)?=))([^#\&\?]*).*/

  def self.ransackable_attributes(auth_object = nil)
    ["name", "link", "access_level", "order", "item_type", "item_id"]
  end

  def video_id
    id = YOUTUBE_ID_REGEX.match(link)

    return :youtube, id[1] if id.present?

    return :facebook, CGI.escape(link) if link.include?('fb.watch') || link.include?('facebook.')

    return nil
  end

  def generate_specific_embed
    service, id = video_id

    return case service
           when :youtube
             "src=\"https://www.youtube-nocookie.com/embed/#{id}\""
           when :facebook
             "src=\"https://www.facebook.com/plugins/post.php?href=#{id}&width=#{VIDEO_EMBED_WIDTH}&show_text=true&height=#{VIDEO_EMBED_HEIGHT}&appId\" style=\"border:none;overflow:hidden\" scrolling=\"no\""
           end
  end

  def embed_code
    specific_part = generate_specific_embed

    return 'The video link is not valid.' if specific_part.nil?

    return "<iframe #{specific_part} #{SHARED_ATTRIBUTES}></iframe>".html_safe
  end

  def link_is_valid
    errors.add(:link, 'is not a valid YouTube or Facebook video link') if video_id.nil?
  end
end
