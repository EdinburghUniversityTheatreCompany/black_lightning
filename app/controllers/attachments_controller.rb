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

    # An attachment whose file has gone is a missing page, the same as an unknown slug. Returning
    # a string here did not render anything - the action fell through to an implicit render of a
    # template this controller does not have.
    raise ActiveRecord::RecordNotFound, "There is no file attached." unless @attachment.file.attached?

    response.headers["Content-Type"] = @attachment.file.content_type
    response.headers["Content-Security-Policy"] = "sandbox"

    inline_ok = %w[application/pdf image/png image/jpeg image/gif image/webp].include?(@attachment.file.content_type)
    disposition = inline_ok ? "inline" : "attachment"
    response.headers["Content-Disposition"] = "#{disposition}; #{@attachment.file.filename}"

    if params[:style]&.to_s&.downcase == "thumb" && @attachment.file.image?
      variant = @attachment.file.blob.variant(helpers.thumb_variant).processed

      @attachment.file.blob.service.download(variant.key) do |chunk|
        response.stream.write(chunk)
      end
    else
      @attachment.file.download do |chunk|
        response.stream.write(chunk)
      end
    end
    # The record says there is a file, but the storage service has no object under that key, so
    # there is nothing to serve. Show the visitor a 404, but still report it: a blob that has gone
    # missing from storage is data loss, not a bad request.
  rescue ActiveStorage::FileNotFoundError => e
    Honeybadger.notify(e, context: {
      attachment_id: @attachment.id,
      blob_key: @attachment.file.key,
      blob_filename: @attachment.file.filename.to_s
    })

    report_404(e)
  end
end
