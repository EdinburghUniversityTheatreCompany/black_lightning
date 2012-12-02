##
# Defines attachments for Admin::EditableBlock.
#
#--
# TODO: Possibly should be moved to Admin namespace?
#++
#
# Uses paperclip to store the file. See AttachmentController for fetching of attachments.
##

class Attachment < ActiveRecord::Base
  belongs_to :editable_block, :class_name => "Admin::EditableBlock"

  validates :name, :presence => true, :uniqueness => true

  has_attached_file :file

  attr_accessible :name, :file
end
