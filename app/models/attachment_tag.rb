# == Schema Information
#
# Table name: attachment_tags
#
# *id*::          <tt>bigint, not null, primary key</tt>
# *name*::        <tt>string(255)</tt>
# *description*:: <tt>text(65535)</tt>
# *created_at*::  <tt>datetime, not null</tt>
# *updated_at*::  <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
class AttachmentTag < ApplicationRecord
  validates :name, :description, presence: true
  validates :name, uniqueness: { case_sensitive: false }

  has_and_belongs_to_many :attachments, optional: true

  normalizes :name, with: -> (name) { name&.strip }

  default_scope { order(:ordering) }

  def self.ransackable_attributes(auth_object = nil)
    %w[description name ordering id]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[attachments]
  end
end
