# frozen_string_literal: true

# Overrides ActiveStorage's representations controller so a variant that fails to process
# answers 404, reported to Honeybadger with the blob's details, instead of 500.
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
    # A forged variation key is someone probing for arbitrary transformations. Upstream rescues
    # this in the set_representation callback, which this override replaces, so it must be
    # rescued here. Deliberately not reported: a rejected forgery is not our bug.
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    head :not_found
    # LoadError (libvips missing) is not a StandardError, so it must be listed.
  rescue Vips::Error, LoadError => e
    Honeybadger.notify(e)
    head :not_found
  end
end
