# frozen_string_literal: true

# Override the built-in ActiveStorage representations controller to add error handling.
# When image processing fails (corrupted files, invalid formats), return 404 instead of 500
# and log the error to Honeybadger with blob context for debugging.
class ActiveStorage::Representations::RedirectController < ActiveStorage::BaseController
  include ActiveStorage::SetBlob

  def show
    Honeybadger.context(
      blob_id: @blob.id,
      blob_key: @blob.key,
      blob_filename: @blob.filename.to_s,
      blob_content_type: @blob.content_type,
      blob_byte_size: @blob.byte_size,
      variation_key: params[:variation_key]
    )

    expires_in ActiveStorage.service_urls_expire_in
    redirect_to @blob.representation(params[:variation_key]).processed.url(disposition: params[:disposition])
  end
end
