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
class Attachment < ApplicationRecord
  belongs_to :editable_block, class_name: 'Admin::EditableBlock'

  validates :name, presence: true, uniqueness: true
  validate  :check_file_size

  has_attached_file :file,
                    url: '/attachments/:slug/:style',
                    convert_options: { thumb: '-quality 75 -strip' },
                    path: ':rails_root/uploads/attachments/:id_partition/:style.:extension',
                    styles: (lambda do |a|
                      if /image\/.+/.match a.instance.file_content_type
                        { thumb: '192x100#', display: '700x700' }
                      else
                        {}
                      end
                    end)

  do_not_validate_attachment_file_type :file

  def slug
    return name
  end

  def check_file_size
    # Restrict file size for images:
    if file_file_size > 1.megabytes && (/image\/.+/.match file_content_type)
      errors.add(:file, 'Attached images must be under 1MB in size.')
    end
  end
end
