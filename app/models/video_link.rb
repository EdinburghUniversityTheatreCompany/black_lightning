# == Schema Information
#
# Table name: video_links
# Database name: primary
#
#  id           :bigint           not null, primary key
#  access_level :integer          default(1), not null
#  item_type    :string(255)
#  link         :string(255)      not null
#  name         :string(255)      not null
#  order        :integer
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  item_id      :bigint
#
# Indexes
#
#  index_video_links_on_item_type_and_item_id  (item_type,item_id)
#
class VideoLink < ApplicationRecord
  belongs_to :item, polymorphic: true

  validate :link_is_valid
  validates :name, :link, :access_level, presence: true

  normalizes :name, with: ->(name) { name&.strip }

  default_scope -> { order(order: :asc) }

  # They're the same, so why not?
  ACCESS_LEVELS = Attachment::ACCESS_LEVELS

  VIDEO_EMBED_WIDTH = 700
  VIDEO_EMBED_HEIGHT = 400

  SHARED_ATTRIBUTES = "width=\"#{VIDEO_EMBED_WIDTH}\" height=\"#{VIDEO_EMBED_HEIGHT}\" frameborder=\"0\" allowfullscreen=\"true\" allow=\"autoplay; clipboard-write; encrypted-media; picture-in-picture; web-share\" class=\"w-full\""

  YOUTUBE_ID_REGEX = %r{^.*(?:(?:youtu\.be\/|v\/|vi\/|u\/\w\/|embed\/)|(?:(?:watch)?\?v(?:i)?=|\&v(?:i)?=))([^#\&\?]*).*}

  def self.ransackable_attributes(auth_object = nil)
    [ "name", "link", "access_level", "order", "item_type", "item_id" ]
  end

  def video_id
    id = YOUTUBE_ID_REGEX.match(link)

    return :youtube, id[1] if id.present?

    return :facebook, CGI.escape(link) if link.include?("fb.watch") || link.include?("facebook.")

    nil
  end

  def generate_specific_embed
    service, id = video_id

    case service
    when :youtube
             "src=\"https://www.youtube-nocookie.com/embed/#{id}\""
    when :facebook
             "src=\"https://www.facebook.com/plugins/post.php?href=#{id}&width=#{VIDEO_EMBED_WIDTH}&show_text=true&height=#{VIDEO_EMBED_HEIGHT}&appId\" style=\"border:none;overflow:hidden\" scrolling=\"no\""
    end
  end

  def embed_code
    specific_part = generate_specific_embed

    return "The video link is not valid." if specific_part.nil?

    "<iframe #{specific_part} #{SHARED_ATTRIBUTES}></iframe>".html_safe
  end

  def authorizable_item
    item
  end

  def link_is_valid
    errors.add(:link, "is not a valid YouTube or Facebook video link") if video_id.nil?
  end
end
