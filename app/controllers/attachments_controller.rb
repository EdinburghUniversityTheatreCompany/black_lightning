##
# Controller for Attachment.
##
class AttachmentsController < ApplicationController
  skip_authorization_check
  ##
  # Returns the file associated with the attachment.
  #
  # Checks permission based on access to the attachment itself and to the attached item.
  ##
  def file
    @attachment = Attachment.find_by_name!(params[:slug])

    authorize!(:show, @attachment)


    # TODO: Make this better. It should preferably go into the ability but it's a bit fiddly to have it there.
    attachment_item = @attachment.item

    attachent_item = attachment_item.answerable if attachment_item.is_a?(Admin::Answer)
    authorize!(:show, attachment_item)

    return 'There is no file attached' unless @attachment.file.attached?

    response.headers['Content-Type'] = @attachment.file.content_type
    response.headers['Content-Disposition'] = "inline; #{@attachment.file.filename}"

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
