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
require_relative "../lib/cloudflare_ips"
require_relative "../app/middleware/cloudflare_ip_sanitizer"
require_relative "../app/middleware/malformed_request_handler"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# We use none of RubyLLM's acts_as_chat / acts_as_message ActiveRecord integration — both
# call sites (Reimbursements::Extractor, Reimbursements::AiChecker) build chats through
# RubyLLM.chat — but the gem's railtie includes ONE of its two acts_as modules into
# ActiveRecord::Base either way, and choosing the legacy one prints a deprecation warning
# on every single process boot: every rake task, every test run, every console.
#
# This has to be set HERE rather than in config/initializers/ruby_llm.rb, where the rest of
# the RubyLLM config lives. The railtie reads the flag from an `ActiveSupport.on_load
# :active_record` hook, and ActiveRecord::Base has already loaded (during Rails' own
# active_record railtie initializers) by the time config/initializers/* run.
#
# The new module's only side effect for us is defaulting `model_registry_source` to its
# ActiveRecord source, which is harmless: with no registry model class configured its
# `read` returns [] (it rescues everything), so RubyLLM falls back to the bundled JSON
# registry that our model ids already resolve from.
RubyLLM.configure { |config| config.use_new_acts_as = true }

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

    # Strip spoofed HTTP_CLIENT_IP headers from Cloudflare requests
    config.middleware.insert_before ActionDispatch::RemoteIp, CloudflareIpSanitizer

    # Return 400 (instead of an uncaught 500) for malformed requests that Rack
    # cannot parse — e.g. bots POSTing gzip-encoded multipart bodies with a
    # missing boundary. Rack::MethodOverride raises these outside
    # ActionDispatch::ShowExceptions, so they must be caught here.
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

    config.action_mailer.default_url_options = { host: "www.bedlamtheatre.co.uk" }

    # Use custom delivery job that inherits from ApplicationJob
    # This gives all emails (including Devise) SMTP retry logic with exponential backoff
    config.action_mailer.delivery_job = "MailDeliveryJob"

    config.active_storage.variant_processor = :vips

    if ENV["HONEYBADGER_API_KEY"].present?
      Honeybadger.configure do |config|
        config.api_key = ENV["HONEYBADGER_API_KEY"]
      end
    end

    config.start_year = 1871

    # --- Reimbursements bank-details encryption at rest ---------------------
    # ActiveRecord Encryption protects the payee bank details
    # (Reimbursements::PaymentDetails + the Expense third-party override trio).
    # Key material by environment:
    #   production  -> config/credentials/production.yml.enc under
    #                  `active_record_encryption:` (Rails' active_record railtie
    #                  reads those automatically; nothing is wired here).
    #   development -> REIMBURSEMENTS_AR_ENCRYPTION_PRIMARY_KEY /
    #                  _DETERMINISTIC_KEY / _KEY_DERIVATION_SALT from ENV (fnox),
    #                  falling back to the throwaway literals below. Dev
    #                  credentials are PUBLIC, so real key material must never
    #                  live in development.yml.enc.
    #   test        -> literal dummy keys in config/environments/test.rb.
    #
    # The rollout is finished: production was backfilled on 2026-07-26 (48 rows
    # across six columns, all verified as ciphertext), so reading plaintext is
    # no longer tolerated and a stray unencrypted value now raises instead of
    # being served. Turning this back on would silently reopen the cleartext
    # read path, so only do it deliberately and temporarily — encrypting a NEW
    # column means setting it true, deploying, backfilling, and turning it off
    # again. docs/reimbursements/encryption-rollout.md has the sequence, and
    # reimbursements:encrypt_backfill cannot run at all while this is false,
    # since it has to read the plaintext to rewrite it.
    config.active_record.encryption.support_unencrypted_data = false

    # Rails auto-injects a `validate_column_size` length validation on every
    # encrypted attribute, but it measures the DECRYPTED value against the
    # column limit — the wrong value, since it is the much longer ciphertext
    # that has to fit, so it cannot catch an overflow. It also breaks
    # `database_consistency`, which walks the validators and hits Rails'
    # lazily-registered length validation mid-iteration ("can't add a new key
    # into hash during iteration"), silently dropping both encrypted models from
    # that step's coverage. Column fit is handled instead by wide enough columns
    # plus explicit plaintext length validations on the models.
    config.active_record.encryption.validate_column_size = false

    if Rails.env.development?
      # Throwaway fallbacks so a dev shell without the fnox exports can still
      # write an expense: an encrypted attribute needs a key on write even when
      # it is blank, so with none configured every Expense.create! raises
      # "Missing Active Record encryption credential". These protect nothing —
      # they are published in the repo and the dev database holds no real bank
      # details. Never reuse them anywhere data matters.
      config.active_record.encryption.primary_key =
        ENV["REIMBURSEMENTS_AR_ENCRYPTION_PRIMARY_KEY"].presence || "dev-only-insecure-primary-key"
      config.active_record.encryption.deterministic_key =
        ENV["REIMBURSEMENTS_AR_ENCRYPTION_DETERMINISTIC_KEY"].presence ||
        "dev-only-insecure-deterministic-key"
      config.active_record.encryption.key_derivation_salt =
        ENV["REIMBURSEMENTS_AR_ENCRYPTION_KEY_DERIVATION_SALT"].presence ||
        "dev-only-insecure-key-derivation-salt"
    end

    # Set image loading to lazy.
    config.action_view.image_loading = "lazy"

  # Use AdminController as base controller
  config.mission_control.jobs.base_controller_class = "Admin::JobsController"

  # Disable HTTP Basic Auth for MissionControl
  config.mission_control.jobs.http_basic_auth_enabled = false
  end
end
