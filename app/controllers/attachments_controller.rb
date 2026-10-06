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

    raise ActiveRecord::RecordNotFound, "There is no file attached." unless @attachment.file.attached?

    response.headers["Content-Type"] = @attachment.file.content_type
    response.headers["Content-Security-Policy"] = "sandbox"

    inline = %w[application/pdf image/png image/jpeg image/gif image/webp].include?(@attachment.file.content_type)
    response.headers["Content-Disposition"] = ActionDispatch::Http::ContentDisposition.format(
      disposition: inline ? "inline" : "attachment", filename: @attachment.file.filename.to_s
    )

    if params[:style].to_s.casecmp?("thumb") && @attachment.file.image?
      variant = @attachment.file.blob.variant(helpers.thumb_variant).processed

      @attachment.file.blob.service.download(variant.key) do |chunk|
        response.stream.write(chunk)
      end
    else
      @attachment.file.download do |chunk|
        response.stream.write(chunk)
      end
    end
    # Reported as well as 404ed: a blob missing from storage is data loss, not a bad link.
  rescue ActiveStorage::FileNotFoundError => e
    Honeybadger.notify(e, context: {
      attachment_id: @attachment.id,
      blob_key: @attachment.file.key,
      blob_filename: @attachment.file.filename.to_s
    })

    report_404(e)
  end
end
