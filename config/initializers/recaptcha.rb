Recaptcha.configure do |config|
  config.site_key = Rails.application.credentials[:recaptcha][Rails.env.to_sym][:site_key]
  config.secret_key = Rails.application.credentials[:recaptcha][Rails.env.to_sym][:secret_key]
 end