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

gem "json"
gem "kaminari"
gem "commonmarker"

gem "icalendar"

gem "solid_queue"
gem "solid_cache"
gem "mission_control-jobs"

# Spreadsheet libraries — each pulls a sizeable Nokogiri-based class tree but is
# only touched by occasional admin/finance actions (report downloads, the BACS
# build, membership imports). require:false keeps them out of every process's
# boot heap; each is `require`d at its call site (see bacs_xlsx.rb, workbook.rb,
# lib/reports/*, import_parsing.rb).
gem "caxlsx", require: false
gem "roo", require: false  # For reading xlsx files (membership imports)
gem "rubyXL", require: false # Fill the EUSA BACS xlsx template in place, preserving styling (reimbursements Build Batch)
gem "rqrcode"

gem "ruby_llm" # Unified LLM API (Gemini) for reimbursements AI receipt extraction + expense checks

gem "silencer"

gem "active_storage_validations"
gem "aws-sdk-s3", require: false
gem "image_processing"
gem "ruby-vips"

gem "chronic"
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

# Caches compiled Ruby (ISeq) and resolved require paths to tmp/cache/bootsnap,
# so every boot after the first skips re-parsing the app and its gems. Rails
# ships this by default; this app predates that and never picked it up.
gem "bootsnap", require: false

gem "vite_rails"
gem "view_component"

# These two must NOT be in the :test group. They attach a Binding to
# exceptions, and a Binding cannot be marshalled -- so under `parallelize`
# every test failure becomes an unreportable worker crash
# ("no _dump_data is defined for class Binding") instead of a readable failure.
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

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
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

  gem "html_acceptance"
end


# Deploy with Kamal. Kamal is a local/CI deploy CLI — it never runs inside the
# app process, so keeping it (and its net-ssh key deps bcrypt_pbkdf/ed25519) in
# :development keeps sshkit/net-ssh/thor out of every Puma + job process's heap.
gem "kamal", "~> 2.0", require: false, group: :development
gem "bcrypt_pbkdf", require: false, group: :development
gem "ed25519", require: false, group: :development

# thruster is a runtime HTTP/2 proxy in front of Puma — it stays in the image.
gem "thruster"

# Guards against unsafe migrations (NOT NULL adds, column removes, in-transaction backfills).
# Runtime gem (ungrouped, not require:false): its initializer references the StrongMigrations
# constant in every environment, so a :development-only gem would crash the test/production boot.
gem "strong_migrations"

gem "bundler-audit", "~> 0.9.3", group: :development
