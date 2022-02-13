#++
#
# See AttachmentController for fetching of attachments.
#
# Note that attachments are not stored in the public directory to prevent them from being
# accessed without authentication.
#
# == Schema Information
#
# Table name: attachments
#
# *id*::                <tt>integer, not null, primary key</tt>
# *editable_block_id*:: <tt>integer</tt>
# *name*::              <tt>string(255)</tt>
# *file_file_name*::    <tt>string(255)</tt>
# *file_content_type*:: <tt>string(255)</tt>
# *file_file_size*::    <tt>integer</tt>
# *file_updated_at*::   <tt>datetime</tt>
# *created_at*::        <tt>datetime, not null</tt>
# *updated_at*::        <tt>datetime, not null</tt>
#--
# == Schema Information End
#++

class Attachment < ApplicationRecord
  include NameHelper

  belongs_to :item, polymorphic: true

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :file, attached: true
  validates :access_level, presence: true

  has_and_belongs_to_many :attachment_tags, optional: true

  has_one_attached :file

  default_scope -> { order('name ASC') }

  ACCESS_LEVELS = [
    ['Grid-Based', 0],
    ['Member', 1],
    ['Everyone', 2]
  ].freeze

  def slug
    return name
  end

  def item_name
    return 'No Item' if item.nil?

    if item_type == 'Admin::Answer'
      return 'No Answerable for Item' if item.answerable.nil?

      extra = if item.answerable.event.present?
                " for #{get_object_name(item.answerable.event)}"
              else
                ''
              end

      return "#{get_object_name(item.answerable)}#{extra}"
    else
      return get_object_name(item)
    end
  end
end
