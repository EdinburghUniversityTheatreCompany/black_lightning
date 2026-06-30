##
# Nothing really interesting about news. It's news.
#
# == Schema Information
#
# Table name: news
# Database name: primary
#
#  id                 :integer          not null, primary key
#  body               :text(16777215)
#  image_content_type :string(255)
#  image_file_name    :string(255)
#  image_file_size    :integer
#  image_updated_at   :datetime
#  publish_date       :datetime
#  show_public        :boolean
#  slug               :string(255)
#  title              :string(255)
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  author_id          :integer
#
# Indexes
#
#  index_news_on_author_id                     (author_id)
#  index_news_on_show_public_and_publish_date  (show_public,publish_date)
#  index_news_on_slug                          (slug)
#
class News < ApplicationRecord
  # Length validations enforcing database column limits
  validates :title, length: { maximum: 255 }
  validates :body, length: { maximum: 16777215 }
  validates :slug, length: { maximum: 255 }
  validates :image_file_name, length: { maximum: 255 }
  validates :image_content_type, length: { maximum: 255 }
  include Sluggable

  resourcify

  ##
  # Use the format id-slug for urls. e.g. /news/1-mynews
  ##
  def to_param
    "#{id}-#{slug}"
  end

  belongs_to :author, class_name: "User"

  validates :title, :body, :publish_date, presence: true
  validates :slug, presence: true, uniqueness: { case_sensitive: false }

  # News should always be ordered by publish_date DESC
  default_scope -> { order("publish_date DESC") }

  # Callbacks
  before_validation :generate_slug_from_title

  scope :current, -> { where([ "publish_date <= ?", Time.current ]) }

  has_one_attached :image

  validates :image, content_type: %i[png jpg jpeg gif webp]

  normalizes :title, :slug, with: ->(value) { value&.strip }

  def self.ransackable_attributes(auth_object = nil)
    %w[body publish_date show_public slug title]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[author image_attachment image_blob roles]
  end

  ##
  # Generates a default image for the news item. If extra artwork is added, increase the base of the modulo call.
  #
  # NOTE: The first image must have filename 0.png - remember that in modulo 2 (for example), valid numbers are 0,1 (not 2)!
  ##
  def fetch_image
    number = id.modulo(2)
    image.attach(ApplicationController.helpers.default_image_blob("news/#{number}.png")) unless image.attached?

    image
  end

  private

  def generate_slug_from_title
    return unless title.present?

    # If we have an existing slug and the title didn't change, don't modify
    return if slug.present? && !title_changed?

    base_slug = title.to_url

    # If title changed, only update if current slug looks auto-generated from old title
    if title_changed? && slug.present?
      old_title = title_was&.to_url
      # For new records title_was is nil, so treat any pre-set slug as manually set
      return if old_title.nil?
      # Only update if the current slug matches what would have been auto-generated from the old title
      # This indicates it was auto-generated, not manually set
      unless slug == old_title || slug.start_with?("#{old_title}-")
        return # Slug was manually set, don't change it
      end
    end

    # Find a unique slug by appending numbers if needed
    candidate_slug = base_slug
    counter = 1

    while News.where.not(id: id).where("LOWER(slug) = ?", candidate_slug.downcase).exists?
      candidate_slug = "#{base_slug}-#{counter}"
      counter += 1
    end

    self.slug = candidate_slug
  end

  public

  # Display the body up to the first line break after 140 characters.
  def preview
    content = body

    begin
      preview = String.new(encoding: Encoding::UTF_8)

      while content.present?
        partition = content.partition(/(\n)|(<\/p>)/)

        preview = preview.concat(partition.first)

        if preview.length < 140 && partition[2].present?
          preview = preview.concat(partition[1])
          content = partition[2]
        else
          break
        end
      end

      preview
    rescue
      # :nocov:
      "There was an error rendering a preview for this news item."
      # :nocov:
    end
  end
end
