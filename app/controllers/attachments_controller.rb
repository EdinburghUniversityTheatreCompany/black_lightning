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
  def file
    @attachment = Attachment.find_by_name!(params[:slug])

    authorize!(:access, :backend) if @attachment.editable_block.admin_page

    return 'There is no file attached' unless @attachment.file.attached?

    response.headers["Content-Type"] = @attachment.file.content_type
    response.headers["Content-Disposition"] = "inline; #{@attachment.file.filename}"
    
    representation = nil

    if params[:style]&.to_s&.downcase == 'thumb' && @attachment.file.image?
      variant = @attachment.file.blob.variant(helpers.thumb_variant).processed

      @attachment.file.blob.service.download(variant.key) do |chunk|
        response.stream.write(chunk)
      end
    else
      @attachment.file.download do |chunk|
        response.stream.write(chunk)
      end
    end
  end
end
