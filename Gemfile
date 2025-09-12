source "http://rubygems.org"

ruby File.read(".ruby-version").strip

gem "rails", "~> 8.0"

gem "mysql2", github: "mickzijdel/mysql2", branch: "master"

gem "cssbundling-rails"
gem "jsbundling-rails"
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

gem "cocoon"
gem "json"
gem "kaminari"
gem "kramdown"

gem "daemons"
gem "delayed_job_active_record"

gem "caxlsx"
gem "leaflet-rails"
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
gem "rack", "~> 2.0"
gem "rack-cors"

gem "stringex"

gem "honeybadger"

gem "csv"

group :development, :test do
  # Use Puma as the app server
  gem "puma"

  gem "byebug"
  gem "spring"

  gem "better_errors"
  gem "binding_of_caller"

  gem "rails-controller-testing"
  gem "rdoc"
  gem "rubocop-rails-omakase"
  gem "rubocop-faker"

  # Adds support for Capybara system testing and selenium driver
  gem "capybara", ">= 2.15"
  gem "selenium-webdriver"
  # Easy installation and use of web drivers to run system tests with browsers
  gem "webdrivers"

  gem "factory_bot_rails"

  gem "coffee-script-source", "1.12.2"
  gem "tzinfo-data"

  gem "annotate"

  gem "bullet"

  gem "faker"

  gem "test-prof"

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

# Deploy with Capistrano
gem "capistrano3-delayed-job"
gem "capistrano-rails"
gem "capistrano-rvm"

gem "bcrypt_pbkdf"
gem "ed25519"
