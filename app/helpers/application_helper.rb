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

  # Generates a stable proxy URL for an ActiveStorage blob, attachment, or variant.
  # Proxy URLs are served through Rails with long-lived Cache-Control headers,
  # unlike signed S3 redirect URLs which expire and change on every request.
  # Only use this for public-facing images — proxy URLs do not expire.
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

  # These should probably live somewhere else

  def xts_widget(xts_id)
    "<div id='tickets-#{xts_id}' class='xtsprodates'></div>
<script src='http://www.xtspro.com/book/book.js'></script>
<script>XTSPRO.insert_dates('BT', #{xts_id}, '#tickets-#{xts_id}');</script>".html_safe
  end

  def spark_seat_widget(spark_seat_slug)
    """
      <div class=\"spark-container\" data-event-slug=\"#{spark_seat_slug}\" data-load-styles=\"bootstrap2\">
        One moment please...
      </div>
      <script src='https://book.sparkseat.com/scripts/loader.js' crossorigin='anonymous'></script>
    """.html_safe
  end
end
