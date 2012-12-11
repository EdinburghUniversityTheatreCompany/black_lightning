##
# Controller for Attachment.
##
class AttachmentsController < ApplicationController

  ##
  # Returns the file associated with the attachment.
  #
  # If the attachments EditableBlock has the admin_page attribute set to
  # true, ensures the user has access to the backend first.
  ##
  def show
    @attachment = Attachment.find_by_name(params[:id])

    if @attachment.editable_block.admin_page then
      authorize! :access, :backend
    end

    send_file @attachment.file.path, :x_sendfile => true, :type => @attachment.file.content_type, :disposition => "inline", :filename => @answer.file.original_filename
  end
end
