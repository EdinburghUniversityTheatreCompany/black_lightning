# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    # Nothing is loaded from pretix.eu: the shop is a custom domain and serves the widget's own
    # script and stylesheet, and the widget bundle never calls pretix.eu back.
    policy.script_src :self, "https://tickets.bedlamtheatre.co.uk", "https://apis.google.com", :unsafe_inline, :unsafe_eval
    # Allow @vite/client to hot reload javascript changes in development
    policy.script_src *policy.script_src, :unsafe_eval, "http://#{ ViteRuby.config.host_with_port }" if Rails.env.development?

    # You may need to enable this in production as well depending on your setup.
    # policy.script_src *policy.script_src, :blob if Rails.env.test?

    # The pretix widget's stylesheet is served by the shop itself, not by pretix.eu (which has
    # no widget CSS: /widget/v1.en.css there redirects to a 404). See PretixHelper.
    policy.style_src :self, :unsafe_inline, "https://tickets.bedlamtheatre.co.uk"
    # Allow @vite/client to hot reload style changes in development
    policy.style_src *policy.style_src, :unsafe_inline if Rails.env.development?

    # style-src-elem is enforced separately by browsers for <link> and <style> elements.
    # Needed for the pretix widget stylesheet: linked by shared/_pretix_widget on a show page,
    # injected dynamically by javascript/lib/pretix.js in the Buy Tickets modal.
    policy.style_src_elem :self, :unsafe_inline, "https://tickets.bedlamtheatre.co.uk"

    # :self is required for the reimbursements receipt viewer, which frames a
    # receipt PDF at its own (proxied, same-origin) Active Storage URL so the
    # browser's native PDF viewer renders it in the page. frame-src does NOT
    # inherit default-src once it is set explicitly, so without :self here every
    # in-page PDF preview is blocked.
    policy.frame_src :self, "https://tickets.bedlamtheatre.co.uk", "https://calendar.google.com", "https://accounts.google.com", "https://www.facebook.com", "https://www.youtube-nocookie.com"
    policy.img_src :self, :data, :https
    policy.font_src :self
    policy.connect_src :self, "https://tickets.bedlamtheatre.co.uk", "https://www.gstatic.com", "https://apis.google.com", "https://clients6.google.com", "https://www.googleapis.com", "https://calendar.googleapis.com", "https://bedlam-theatre-website.s3.eu-central-1.wasabisys.com"
    # Allow @vite/client to hot reload changes in development
    policy.connect_src *policy.connect_src, "ws://#{ ViteRuby.config.host_with_port }" if Rails.env.development?

    # Specify URI for violation reports
    # policy.report_uri "/csp-violation-report-endpoint"
  end

  # Generate session nonces for permitted importmap, inline scripts, and inline styles.
  # config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  # config.content_security_policy_nonce_directives = %w(script-src style-src)

  # Automatically add `nonce` to `javascript_tag`, `javascript_include_tag`, and `stylesheet_link_tag`
  # if the corresponding directives are specified in `content_security_policy_nonce_directives`.
  # config.content_security_policy_nonce_auto = true

  # Report violations without enforcing the policy (report-only mode).
  # This allows us to monitor violations in development without breaking functionality.
  # config.content_security_policy_report_only = true
end
