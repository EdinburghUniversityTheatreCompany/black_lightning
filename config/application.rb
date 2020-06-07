require_relative 'boot'

require 'rails/all'
require 'sprockets/railtie'

if defined?(Bundler)
  # If you precompile assets before deploying to production, use this line
  Bundler.require(*Rails.groups(assets: %w(development test)))
  # If you want your assets lazily compiled in production, use this line
  # Bundler.require(:default, :assets, Rails.env)
end

module ChaosRails
  class Application < Rails::Application
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 5.2

    # Custom directories with classes and modules you want to be autoloadable.
    config.eager_load_paths << "#{config.root}/lib"

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    config.time_zone = 'London'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de

    # Enforce whitelist mode for mass assignment.
    # This will create an empty whitelist of attributes available for mass-assignment for all models
    # in your app. As such, your models will need to explicitly whitelist or blacklist accessible
    # parameters by using an attr_accessible or attr_protected declaration.
    # config.active_record.whitelist_attributes = true

    # Handle error routes:
    config.exceptions_app = routes

    # Protect against csrf attacks by checking origin matches sites address
    config.action_controller.forgery_protection_origin_check = true

    config.active_job.queue_adapter = :delayed_job

    config.action_mailer.default_url_options = { host: 'www.bedlamtheatre.co.uk' }

    if Rails.application.secrets.honeybadger
      Honeybadger.configure do |config|
        config.api_key = Rails.application.secrets.honeybadger['api_key']
      end
    end
  end
end
