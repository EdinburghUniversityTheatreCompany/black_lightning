# == Schema Information
#
# Table name: attachments
#
#  id                :integer          not null, primary key
#  editable_block_id :integer
#  name              :string(255)
#  file_file_name    :string(255)
#  file_content_type :string(255)
#  file_file_size    :integer
#  file_updated_at   :datetime
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#

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
