##
# Represents a section in a page that can be edited using the Admin pages.
#
# IMPORTANT: The admin_page property is used to ensure that visitors that are not logged in
# cannot access any Attachment belonging to this block.
#

# == Schema Information
#
# Table name: admin_editable_blocks
# Database name: primary
#
#  id         :integer          not null, primary key
#  admin_page :boolean
#  content    :text(16777215)
#  group      :string(255)
#  name       :string(255)
#  ordering   :bigint
#  url        :string(255)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_admin_editable_blocks_on_ordering  (ordering)
#
class Admin::EditableBlock < ApplicationRecord
  # Length validations enforcing database column limits
  validates :name, length: { maximum: 255 }
  validates :content, length: { maximum: 16777215 }
  validates :group, length: { maximum: 255 }
  validates :url, length: { maximum: 255 }
  include MdHelper

  resourcify
  has_paper_trail meta: { version_note: :version_note }

  include AttachmentItem
  include Versionable

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :url, uniqueness: { case_sensitive: false }, if: :url?

  normalizes :name, with: ->(name) { name&.strip }
  normalizes :url, with: ->(url) { url&.downcase }

  after_commit :clear_navbar_cache

  scope :for_subpage, ->(subpage_type) { where("url LIKE ?", "#{subpage_type}%") }

  def self.groups
    select("`group`").distinct.map(&:group).reject(&:blank?)
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[admin_page content group name ordering url]
  end

  def cached_rendered_content
    Rails.cache.fetch("editable_block_#{id}_#{updated_at.to_i}_v2", expires_in: 7.days) do
      render_markdown(content)
    end
  end

  private

  def clear_navbar_cache
    return if url.blank?

    # Clear cache for each URL prefix, since get_subpage_editable_blocks caches
    # by the full subpage_type path (e.g. "admin/resources"), not just the first segment.
    parts = url.split("/")
    parts.length.times do |i|
      Rails.cache.delete("navbar_editable_blocks/#{parts[0..i].join("/")}")
    end
  end
end
