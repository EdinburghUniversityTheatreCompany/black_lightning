# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    # Nothing is loaded from pretix.eu: the shop domain serves the widget's script and stylesheet.
    policy.script_src :self, "https://tickets.bedlamtheatre.co.uk", "https://apis.google.com", :unsafe_inline, :unsafe_eval
    # Allow @vite/client to hot reload javascript changes in development
    policy.script_src *policy.script_src, :unsafe_eval, "http://#{ ViteRuby.config.host_with_port }" if Rails.env.development?

    # The widget's stylesheet comes from the shop; pretix.eu 404s it. See PretixHelper.
    policy.style_src :self, :unsafe_inline, "https://tickets.bedlamtheatre.co.uk"
    # Allow @vite/client to hot reload style changes in development
    policy.style_src *policy.style_src, :unsafe_inline if Rails.env.development?

    # Browsers enforce style-src-elem separately for <link> and <style>; the pretix widget's
    # stylesheet (shared/_pretix_widget, lib/pretix.js) needs the shop origin here too.
    policy.style_src_elem :self, :unsafe_inline, "https://tickets.bedlamtheatre.co.uk"

    # :self is needed for the reimbursements receipt PDF viewer. frame-src does NOT inherit
    # default-src once set, so without it every in-page PDF preview is blocked.
    policy.frame_src :self, "https://tickets.bedlamtheatre.co.uk", "https://calendar.google.com", "https://accounts.google.com", "https://www.facebook.com", "https://www.youtube-nocookie.com"
    policy.img_src :self, :data, :https
    policy.font_src :self
    policy.connect_src :self, "https://tickets.bedlamtheatre.co.uk", "https://www.gstatic.com", "https://apis.google.com", "https://clients6.google.com", "https://www.googleapis.com", "https://calendar.googleapis.com", "https://bedlam-theatre-website.s3.eu-central-1.wasabisys.com"
    # Allow @vite/client to hot reload changes in development
    policy.connect_src *policy.connect_src, "ws://#{ ViteRuby.config.host_with_port }" if Rails.env.development?
  end
end
