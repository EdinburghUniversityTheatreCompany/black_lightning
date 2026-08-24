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
    redirect_to @blob.representation(params[:variation_key]).processed.url(disposition: params[:disposition]), allow_other_host: true
    # The variation key is signed, so an unsigned or forged one is someone probing
    # whether we will run arbitrary image transformations. Upstream rescues this in
    # ActiveStorage::Representations::BaseController's set_representation callback,
    # which this override replaces by decoding the variation inline — so it has to
    # rescue it too, or the signature check working reads as an application crash.
    # Deliberately not reported: a rejected forgery is not our bug.
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    head :not_found
    # LoadError covers an image backend that fails to load its native library
    # (e.g. ruby-vips/libvips missing). It is not a StandardError, so it must be
    # listed explicitly or the controller would 500 instead of degrading to 404.
  rescue Vips::Error, LoadError => e
    Honeybadger.notify(e)
    head :not_found
  end
end
