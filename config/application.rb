require_relative "boot"

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
require "rails/test_unit/railtie"

require "image_processing/mini_magick"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module ChaosRails
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Edinburgh"
    config.eager_load_paths << "#{config.root}/lib"
    Rails.autoloaders.main.ignore(config.root.join("lib/generators"))

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

    config.action_mailer.default_url_options = { host: "www.bedlamtheatre.co.uk" }

    # Use custom delivery job that inherits from ApplicationJob
    # This gives all emails (including Devise) SMTP retry logic with exponential backoff
    config.action_mailer.delivery_job = "MailDeliveryJob"

    config.active_storage.variant_processor = :vips

    if Rails.application.credentials.try(:honeybadger).try(Rails.env.to_sym).present?
      Honeybadger.configure do |config|
        config.api_key = Rails.application.credentials[:honeybadger][Rails.env.to_sym][:api_key]
      end
    end

    config.start_year = 1871

    # Set image loading to lazy.
    config.action_view.image_loading = "lazy"

  # Use AdminController as base controller
  config.mission_control.jobs.base_controller_class = "Admin::JobsController"

  # Disable HTTP Basic Auth for MissionControl
  config.mission_control.jobs.http_basic_auth_enabled = false
  end
end
