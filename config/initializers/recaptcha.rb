Recaptcha.configure do |config|
  creds = Rails.application.credentials.dig(:recaptcha, Rails.env.to_sym)
  if creds.present?
    config.site_key = creds[:site_key]
    config.secret_key = creds[:secret_key]
  end
 end
