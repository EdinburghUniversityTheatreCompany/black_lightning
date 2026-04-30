# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src :self, "https://pretix.eu", :unsafe_inline, :unsafe_eval
    policy.style_src :self, :unsafe_inline, "https://eutc.azureedge.net"
    policy.img_src :self, :data, :https
    policy.font_src :self
    policy.connect_src :self, "https://tickets.bedlamtheatre.co.uk"
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
  config.content_security_policy_report_only = true
end
