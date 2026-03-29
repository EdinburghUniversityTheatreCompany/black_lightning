Recaptcha.configure do |config|
  creds = Rails.application.credentials.dig(:recaptcha)
  if creds&.dig(:site_key).present?
    config.site_key = creds[:site_key]
    config.secret_key = creds[:secret_key]
  # If we're not in production, just put some placeholders so the recaptcha works
  elsif !Rails.env.production?
    config.site_key = "placeholder"
    config.secret_key = "placeholder"
  end
 end
