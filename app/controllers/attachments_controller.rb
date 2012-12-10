##
# Controller for Attachment.
##
class AttachmentsController < ApplicationController

  ##
  # Redirects to the public url of the attachment.
  #
  # If the attachments EditableBlock has the admin_page attribute set to
  # true, ensures the user has access to the backend first.
  ##
  def show
    @attachment = Attachment.find_by_name(params[:id])

    if @attachment.editable_block.admin_page then
      authorize! :access, :backend
    end

    redirect_to @attachment.file.url
  end
end
