# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # While tests run files are not watched, reloading is not necessary.
  config.enable_reloading = false

  # Eager loading loads your entire application. When running a single test locally,
  # this is usually not necessary, and can slow down your test suite. However, it's
  # recommended that you enable it in continuous integration systems to ensure eager
  # loading is working properly before deploying your code.
  config.eager_load = ENV["CI"].present?

  # Configure public file server for tests with cache-control for performance.
  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }

  # Show full error reports.
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false

  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Store uploaded files on the local file system in a temporary directory.
  config.active_storage.service = :test

  # Disable caching for Action Mailer templates even if Action Controller
  # caching is enabled.
  config.action_mailer.perform_caching = false

  # Tell Action Mailer not to deliver emails to the real world.
  # The :test delivery method accumulates sent emails in the
  # ActionMailer::Base.deliveries array.
  config.action_mailer.delivery_method = :test

  # Unlike controllers, the mailer instance doesn't have any context about the
  # incoming request so you'll need to provide the :host parameter yourself.
  config.action_mailer.default_url_options = { host: "www.example.com" }

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Raise exceptions for disallowed deprecations.
  config.active_support.disallowed_deprecation = :raise

  # Tell Active Support which deprecation messages to disallow.
  config.active_support.disallowed_deprecation_warnings = []

  # Raises error for missing translations.
  config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true

  # Set job adapter for tests
  config.active_job.queue_adapter = :test

  config.after_initialize do
    Prosopite.rails_logger = true
    # Set to true once existing N+1s are resolved to enforce strict mode in CI
    Prosopite.raise = true
    # Known N+1s that are either intentional or need a larger refactor:
    # - Debt reallocation is inherently per-user (pairs debts with attendances/jobs)
    # - users_oldest_debt queries each user's minimum debt date in the mailer loop
    # - Team member user validation fires per-record during event update; Rails nested
    #   attributes don't support preloading associations before validation callbacks.
    #   TODO: preload team member users in GenericEventsController#update before
    #   calling super, or use a different validation strategy.
    # Known N+1s pending larger fixes:
    # - Debt view: 6 per-user aggregate methods per row. TODO: precompute in controller.
    # - News image blobs: ActiveStorage blob loading via image.blob bypasses preloaded
    #   image_attachment includes. TODO: investigate why includes(image_attachment: :blob)
    #   doesn't prevent the join query in shared/_image.erb.
    # - Default image blobs: 2+ different default filenames queried per request.
    #   TODO: bulk-load all default blobs at the start of the news index action.
    # - Picture/gallery form N+1s: pictures in nested forms not preloaded.
    #   TODO: preload via ActiveRecord::Associations::Preloader in edit before_action.
    # - MarketingCreatives profile: category_infos without preloaded pictures/attachments.
    #   TODO: add includes to ProfilesController show action.
    Prosopite.allow_stack_paths = [
      "User#reallocate_maintenance_debts",
      "User#reallocate_staffing_debts",
      "Admin::Debt.users_oldest_debt",
      "generic_events_controller.rb",
      "debts/_index_results.erb",
      "news.rb",
      "active_storage_helper.rb",
      "picture.rb",
      "category_info.rb",
      "_picture_fields.erb",
      "_gallery.html.erb",
      "_image.erb",
      "category_info_factory.rb",
      "event_factory.rb",
      "profiles/show.html.erb"
    ]
  end
end
