require "silencer/rails/logger"

COMPLAINTS_ALIASES = %w[/complaint /complaints /complain /suggestions /suggestion /suggest]

Rails.application.configure do
  config.middleware.swap(
    Rails::Rack::Logger,
    Silencer::Logger,
    config.log_tags,
    silence: %w[/complaints/new] + COMPLAINTS_ALIASES
  )
end
