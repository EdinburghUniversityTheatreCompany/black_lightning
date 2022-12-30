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

  default_scope { order(:ordering) }
end
