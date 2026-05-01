source "http://rubygems.org"

ruby File.read(".ruby-version").strip

gem "rails", "~> 8.1"

gem "mysql2" # , github: "mickzijdel/mysql2", branch: "master"

gem "cssbundling-rails"
gem "jsbundling-rails"
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

gem "json"
gem "kaminari"
gem "commonmarker"

gem "icalendar"

gem "daemons"
gem "delayed_job_active_record"

gem "solid_queue"
gem "solid_cache"
gem "mission_control-jobs"

gem "caxlsx"
gem "roo"  # For reading xlsx files (membership imports)
gem "rqrcode"

gem "silencer"

gem "active_storage_validations"
gem "aws-sdk-s3", require: false
gem "image_processing"
gem "mini_magick"

gem "chronic"
gem "ransack"

gem "nokogiri"

gem "paper_trail"
gem "diffy"
gem "rack", "~> 2.0"
gem "rack-cors"

gem "stringex"

gem "honeybadger"
gem "rack-timeout"
gem "skylight"

gem "csv"

# Use Puma as the app server
gem "puma"

group :development, :test do
  gem "byebug"
  gem "spring"

  gem "better_errors"
  gem "binding_of_caller"

  gem "rails-controller-testing"
  gem "rdoc"
  gem "rubocop-rails-omakase"
  gem "rubocop-faker"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Adds support for Capybara system testing and selenium driver
  gem "capybara", ">= 2.15"
  gem "selenium-webdriver", ">= 4.8.2"

  gem "factory_bot_rails"

  gem "coffee-script-source", "1.12.2"
  gem "tzinfo-data"

  gem "annotate"

  gem "bullet"

  gem "faker"

  gem "test-prof"
  gem "stackprof", ">= 0.2.9", require: false

  gem "rdbg"
  gem "ruby-lsp-rails"
  gem "solargraph", require: false
  gem "foreman"
end

group :test do
  gem "simplecov"
  gem "simplecov-rcov"

  gem "html_acceptance"
end


# Deploy with Kamal
gem "kamal", "~> 2.0"
gem "thruster"

gem "bcrypt_pbkdf"
gem "ed25519"
