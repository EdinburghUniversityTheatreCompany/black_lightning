##
# Nothing really interesting about news. It's news.
#
# == Schema Information
#
# Table name: news
#
# *id*::                 <tt>integer, not null, primary key</tt>
# *title*::              <tt>string(255)</tt>
# *body*::               <tt>text(65535)</tt>
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
class News < ApplicationRecord
  resourcify

  ##
  # Use the format id-slug for urls. e.g. /news/1-mynews
  ##
  def to_param
    "#{id}-#{slug}"
  end

  belongs_to :author, class_name: 'User'

  validates :title, :body, :publish_date, presence: true
  validates :slug, presence: true, uniqueness: { case_sensitive: false }

  # News should always be ordered by publish_date DESC
  default_scope -> { order('publish_date DESC') }

  scope :current, -> { where(['publish_date <= ?', Time.current]) }

  has_one_attached :image

  validates :image, content_type: %i[png jpg jpeg gif]

  normalizes :title, :slug, with: -> (value) { value&.strip }

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

    return image
  end

  # Display the body up to the first line break after 140 characters.
  def preview
    content = body

    begin
      preview = ''

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

      return preview
    rescue
      # :nocov:
      return 'There was an error rendering a preview for this news item.'
      # :nocov:
    end
  end
end
