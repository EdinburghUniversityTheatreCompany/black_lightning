# URLs for the pretix ticket shop.
#
# The shop's own domain, not pretix.eu, serves the widget's script and stylesheet:
# pretix.eu/widget/v1.en.css redirects to a 404, so pointing there renders the widget
# unstyled. Keep in step with the paths in app/javascript/lib/pretix.js, the `baseUrl`
# default in pretix_modal_controller.js, and the shop origin in
# config/initializers/content_security_policy.rb.
module PretixHelper
  SHOP_URL = "https://tickets.bedlamtheatre.co.uk/".freeze

  def pretix_shop_url(path = nil)
    "#{SHOP_URL}#{path}"
  end

  def pretix_event_url(event)
    pretix_shop_url("#{event.pretix_slug}/")
  end

  def pretix_widget_stylesheet_url
    pretix_shop_url("widget/v1.css")
  end
end
