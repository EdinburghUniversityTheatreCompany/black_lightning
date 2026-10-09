source "https://rubygems.org", cooldown: 4

ruby File.read(".ruby-version").strip

gem "rails", "~> 8.1"

gem "mysql2" # , github: "mickzijdel/mysql2", branch: "master"

gem "turbo-rails"
gem "propshaft"

gem "terser"

gem "breadcrumbs_on_rails"
gem "cancancan"
gem "devise"
gem "doorkeeper"
gem "doorkeeper-openid_connect"
gem "recaptcha"
gem "rolify"
gem "simple_form"

# Held at 2.x: json 3 made JSON.parse's options keyword-only, but Rails 8.1's
# ActiveSupport::JSON.decode passes them positionally, so every serialized/JSON column raises
# "wrong number of arguments". Drop once Rails calls it with keywords (plans/deferred-upgrades.md).
gem "json", "< 3"
gem "kaminari"
gem "commonmarker"

gem "icalendar"

gem "solid_queue"
gem "solid_cache"
gem "mission_control-jobs"

# Spreadsheet libraries: large Nokogiri-based class trees used only by occasional admin/finance
# actions. require: false keeps them out of every process's boot heap; each is required at its
# call site.
gem "caxlsx", require: false
gem "roo", require: false  # For reading xlsx files (membership imports)
gem "rubyXL", require: false # Fill the EUSA BACS xlsx template in place, preserving styling (reimbursements Build Batch)
gem "rqrcode"

gem "silencer"

gem "active_storage_validations"
gem "aws-sdk-s3", require: false
gem "image_processing"
gem "ruby-vips"

gem "ransack"

gem "nokogiri"

gem "paper_trail"
gem "diffy"
gem "rack"
gem "rack-cors"

gem "stringex"

gem "honeybadger"
gem "rack-timeout"
gem "skylight"

gem "csv"

# Use Puma as the app server
gem "puma"

gem "bootsnap", require: false

gem "vite_rails"
gem "view_component"

# Must NOT go in :test: they attach an unmarshalable Binding to exceptions, so under `parallelize`
# every failure becomes a worker crash, and BetterErrors::Middleware swallows the app-server
# errors the system tests should catch.
group :development do
  gem "better_errors"
  gem "binding_of_caller"
end

group :development, :test do
  gem "byebug"

  gem "rails-controller-testing"
  gem "rdoc"
  gem "rubocop-rails-omakase"
  gem "rubocop-faker"
  gem "rubocop-view_component", require: false
  gem "rubocop-minitest", require: false
  gem "rubocop-mick", github: "mickzijdel/rubocop-mick", require: false

  gem "brakeman", require: false

  # dev-env standard audits (dev-hooks:dev-env-setup) — run via hk + CI.
  gem "debride", require: false                # dead-method detection
  gem "flay", require: false                   # Ruby structural duplication (advisory)
  gem "fasterer", require: false               # perf anti-pattern advisory
  gem "herb", require: false                   # HTML-aware ERB analyze + lint
  gem "database_consistency", require: false   # model vs schema consistency

  # Adds support for Capybara system testing and selenium driver
  gem "capybara", ">= 2.15"
  gem "selenium-webdriver", ">= 4.8.2"

  gem "factory_bot_rails"

  gem "coffee-script-source", "1.12.2"
  gem "tzinfo-data"

  gem "annotaterb"

  gem "bullet"
  gem "rack-mini-profiler"

  gem "faker"

  gem "test-prof"
  gem "stackprof", ">= 0.2.9"

  gem "rdbg"
  gem "ruby-lsp-rails"
  gem "solargraph", require: false
  gem "foreman"
end

group :test do
  gem "simplecov"
  gem "simplecov-rcov"
end


# Kamal is a deploy CLI that never runs in the app process; keeping it and its net-ssh key deps
# in :development keeps sshkit/net-ssh/thor out of every Puma and job process.
gem "kamal", "~> 2.0", require: false, group: :development
gem "bcrypt_pbkdf", require: false, group: :development
gem "ed25519", require: false, group: :development

# Runtime HTTP/2 proxy in front of Puma; stays in the image.
gem "thruster"

# Ungrouped and not require: false: its initializer references StrongMigrations in every
# environment, so a :development-only gem would crash the test/production boot.
gem "strong_migrations"

gem "bundler-audit", "~> 0.9.3", group: :development
