##
# Defines attachments for Admin::EditableBlock.
#
#--
# TODO: Possibly should be moved to Admin namespace?
#++
#
# Uses paperclip to store the file. See AttachmentController for fetching of attachments.
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
##
class Attachment < ActiveRecord::Base
  belongs_to :editable_block, :class_name => "Admin::EditableBlock"

  validates :name, :presence => true, :uniqueness => true

  has_attached_file :file, :url => "/attachments/#{slug}", :path => ':rails_root/uploads/attachments/:id_partition/:style.:extension'

  attr_accessible :name, :file
end
