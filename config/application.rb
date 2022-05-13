require_relative 'boot'

require "rails"

# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "sprockets/railtie"
require "rails/test_unit/railtie"

require "image_processing/mini_magick"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module ChaosRails
  class Application < Rails::Application
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.

    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 6.1

    # Custom directories with classes and modules you want to be autoloadable.
    config.eager_load_paths << "#{config.root}/lib"
    Rails.autoloaders.main.ignore(config.root.join('lib/generators'))

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

    config.active_storage.variant_processor = :vips

    if Rails.application.secrets.honeybadger
      Honeybadger.configure do |config|
        config.api_key = Rails.application.secrets.honeybadger[:api_key]
      end
    end

    config.start_year = 1871
  end
end
