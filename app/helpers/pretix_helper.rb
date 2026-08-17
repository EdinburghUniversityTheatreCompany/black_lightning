# URLs for the pretix ticket shop.
#
# The shop runs on its own (custom) domain, and that domain — not pretix.eu — is what serves
# the widget's script and stylesheet. pretix.eu has no global widget CSS at all:
# https://pretix.eu/widget/v1.en.css redirects to a 404, so a page pointing there renders the
# widget completely unstyled.
#
# Keep this in step with the `baseUrl` default in
# app/javascript/controllers/pretix_modal_controller.js, and with the shop origin listed in
# config/initializers/content_security_policy.rb (script-src, style-src, style-src-elem,
# frame-src and connect-src all need it).
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

  def pretix_widget_script_url
    pretix_shop_url("widget/v1.en.js")
  end
end
