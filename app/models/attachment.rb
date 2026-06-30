# See AttachmentController for fetching of attachments.
#
# Note that attachments are not stored in the public directory to prevent them from being
# accessed without authentication.
#

# == Schema Information
#
# Table name: attachments
# Database name: primary
#
#  id                :integer          not null, primary key
#  access_level      :integer          default(1), not null
#  file_content_type :string(255)
#  file_file_name    :string(255)
#  file_file_size    :integer
#  file_updated_at   :datetime
#  item_type         :string(255)
#  name              :string(255)
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  editable_block_id :integer
#  item_id           :bigint
#
# Indexes
#
#  index_attachments_on_editable_block_id      (editable_block_id)
#  index_attachments_on_item_type_and_item_id  (item_type,item_id)
#
class Attachment < ApplicationRecord
  # Length validations enforcing database column limits
  validates :name, length: { maximum: 255 }
  validates :file_file_name, length: { maximum: 255 }
  validates :file_content_type, length: { maximum: 255 }
  validates :item_type, length: { maximum: 255 }
  include NameHelper

  belongs_to :item, polymorphic: true, optional: true

  # Sheet-music / music-notation content types are registered with Marcel in
  # config/initializers/sheet_music_mime_types.rb so they resolve correctly here.
  ALLOWED_CONTENT_TYPES = %w[
    application/pdf
    image/png image/jpeg image/gif image/webp
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    application/msword application/vnd.ms-excel
    text/plain
    application/x-musescore application/x-musescore+xml
    application/vnd.recordare.musicxml+xml application/vnd.recordare.musicxml
    audio/midi
    application/x-sibelius
    text/x-lilypond text/vnd.abc
  ].freeze

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :file, attached: true, content_type: ALLOWED_CONTENT_TYPES
  validates :access_level, presence: true

  has_and_belongs_to_many :attachment_tags, optional: true

  has_one_attached :file

  normalizes :name, with: ->(name) { name&.strip }

  default_scope -> { order("name ASC") }

  ACCESS_LEVELS = [
    [ "Grid-Based", 0 ],
    [ "Member", 1 ],
    [ "Everyone", 2 ]
  ].freeze

  def slug
    name
  end

  def authorizable_item
    item.is_a?(Admin::Answer) ? item.answerable : item
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[editable_block_id name]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[editable_block attachment_tags file_blob]
  end

  def item_name
    return "No Item" if item.nil?

    if item_type == "Admin::Answer"
      return "No Answerable for Item" if item.answerable.nil?

      extra = if item.answerable.event.present?
                " for #{get_object_name(item.answerable.event)}"
      else
                ""
      end

      "#{get_object_name(item.answerable)}#{extra}"
    else
      get_object_name(item)
    end
  end
end
