##
# Controller for Attachment.
##
class AttachmentsController < ApplicationController
  skip_authorization_check
  ##
  # Returns the file associated with the attachment.
  #
  # If the attachments EditableBlock has the admin_page attribute set to
  # true, ensures the user has access to the backend first.
  ##
  def show
    @attachment = Attachment.find_by_name!(params[:slug])

    authorize!(:access, :backend) if @attachment.editable_block.admin_page

    send_file @attachment.file.path(params[:style]), x_sendfile: true, type: @attachment.file.content_type, disposition: 'inline', filename: @attachment.file.original_filename
  end
end
