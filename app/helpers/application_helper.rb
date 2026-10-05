module ApplicationHelper
  # It's a bit hacky, but it works.
  # Used by the error pages and subpage layout to decide which layout to use.
  def current_environment(path)
    return "admin" if path[0..6].include?("admin") && current_ability.can?(:access, :backend)

    "application"
  end

  def merge_hash(a, b)
    a.merge(b) do |_key, oldval, newval|
      # http://stackoverflow.com/a/11171921
      (newval.is_a?(Array) ? (oldval + newval) : (oldval << newval)).uniq
    end
  end

  # A stable, long-cached URL for a blob, attachment or variant, unlike a signed S3 redirect,
  # which changes on every request. Public images only: a proxy URL never expires.
  def active_storage_proxy_url(image)
    if image.respond_to?(:variation)
      rails_blob_representation_proxy_url(
        signed_blob_id: image.blob.signed_id,
        variation_key: image.variation.key,
        filename: image.blob.filename
      )
    else
      rails_storage_proxy_url(image)
    end
  end
end
