##
# Represents a section in a page that can be edited using the Admin pages.
#
# IMPORTANT: The admin_page property is used to ensure that visitors that are not logged in
# cannot access any Attachment belonging to this block.
#
# == Schema Information
#
# Table name: admin_editable_blocks
#
# *id*::         <tt>integer, not null, primary key</tt>
# *name*::       <tt>string(255)</tt>
# *content*::    <tt>text(65535)</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
# *admin_page*:: <tt>boolean</tt>
# *group*::      <tt>string(255)</tt>
# *url*::        <tt>string(255)</tt>
# *ordering*::   <tt>bigint</tt>
#--
# == Schema Information End
#++

class Admin::EditableBlock < ApplicationRecord
  resourcify
  has_paper_trail meta: { version_note: :version_note }

  include AttachmentItem
  include Versionable

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :url, uniqueness: { case_sensitive: false }, if: :url?

  normalizes :name, with: ->(name) { name&.strip }
  normalizes :url, with: ->(url) { url&.downcase }

  after_commit :clear_navbar_cache

  def self.groups
    select("`group`").distinct.map(&:group).reject(&:blank?)
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[admin_page content group name ordering url]
  end

  def cached_rendered_content
    Rails.cache.fetch("editable_block_#{id}_#{updated_at.to_i}", expires_in: 7.days) do
      Kramdown::Document.new(content || "", input: "BKramdown").to_html
    end
  end

  private

  def clear_navbar_cache
    section = url&.split("/")&.first
    Rails.cache.delete("navbar_editable_blocks/#{section}") if section.present?
  end
end
