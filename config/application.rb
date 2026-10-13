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

require "image_processing/vips"
require_relative "../app/middleware/client_ip_stripper"
require_relative "../app/middleware/malformed_request_handler"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module ChaosRails
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets rubocop])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Edinburgh"
    config.eager_load_paths << "#{config.root}/lib"
    Rails.autoloaders.main.ignore(config.root.join("lib/generators"))

    config.middleware.insert_before ActionDispatch::RemoteIp, ClientIpStripper

    # Rack::MethodOverride raises on unparseable requests (bots POSTing gzip-encoded multipart
    # bodies with no boundary) outside ShowExceptions, so catch them here: 400, not 500.
    config.middleware.insert_before Rack::MethodOverride, MalformedRequestHandler

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

    config.action_mailer.default_url_options = { host: "bedlamtheatre.co.uk", protocol: "https" }

    # Gives every email, Devise's included, SMTP retries with exponential backoff.
    config.action_mailer.delivery_job = "MailDeliveryJob"

    config.active_storage.variant_processor = :vips

    if ENV["HONEYBADGER_API_KEY"].present?
      Honeybadger.configure do |config|
        config.api_key = ENV["HONEYBADGER_API_KEY"]
      end
    end

    config.start_year = 1871

    # --- Reimbursements bank-details encryption at rest ---------------------
    # ActiveRecord Encryption protects payee bank details (Reimbursements::PaymentDetails and the
    # Expense override trio). Keys: production reads `active_record_encryption:` from its
    # credentials (nothing wired here); development takes REIMBURSEMENTS_AR_ENCRYPTION_* from ENV,
    # else throwaway literals in config/environments/development.rb (the development credentials
    # are public, so never put real keys there); test uses literals in test.rb.
    #
    # The rollout is finished (production backfilled 2026-07-26), so a stray plaintext value now
    # raises instead of being served. Turning this back on reopens the cleartext read path: do it
    # only deliberately and temporarily. Encrypting a NEW column means true, deploy, backfill, false
    # again (docs/reimbursements/encryption-rollout.md), and reimbursements:encrypt_backfill cannot
    # run while this is false because it must read the plaintext.
    config.active_record.encryption.support_unencrypted_data = false

    # Rails' auto-injected `validate_column_size` measures the decrypted value, but the longer
    # ciphertext is what has to fit, so it catches nothing. It also crashes `database_consistency`
    # ("can't add a new key into hash during iteration"). Wide columns plus explicit plaintext
    # length validations on the models do the job.
    config.active_record.encryption.validate_column_size = false

    # Set image loading to lazy.
    config.action_view.image_loading = "lazy"

  config.mission_control.jobs.base_controller_class = "Admin::JobsController"

  config.mission_control.jobs.http_basic_auth_enabled = false
  end
end
