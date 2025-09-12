set :application, "BlackLightning"
set :repo_url,    "git@github.com:EdinburghUniversityTheatreCompany/black_lightning.git"
set :branch,      "main"

set :rails_env, "production"

set :user, "deploy"

set :keep_releases, 4

set :linked_files, %w[config/database.yml config/master.key config/openid_signing_key]
set :linked_dirs, %w[log bundle tmp/pids tmp/cache tmp/sockets public/system public/assets public/packs node_modules uploads storage .duplicacy]

# Ensure native gems like nokogiri build against system libraries on the server
set :default_env, { "BUNDLE_FORCE_RUBY_PLATFORM" => "true" }

# TODO: Run zeitwerk:check
# TODO: Run tests
# TODO: Do a mysql dump

before "deploy:assets:precompile", "deploy:yarn_install"

namespace :deploy do
  after :publishing, :restart do
    on roles(:app), in: :sequence, wait: 5 do
      within release_path do
        execute :touch, "tmp/restart.txt"
      end
    end
  end

  desc "Start solid_queue processes"
  after :migrate_jobs, :start_solid_queue do
    on roles(:app) do
      within release_path do
        with rails_env: fetch(:rails_env) do
          # Stop any existing solid_queue processes
          execute :bundle, :exec, :rails, "solid_queue:stop", raise_on_non_zero_exit: false
          # Start solid_queue
          execute :bundle, :exec, :rails, "solid_queue:start"
        end
      end
    end
  end

  desc "Updates the version file"
  after :publishing, :updateversion do
    on roles(:app) do
      within release_path do
        execute :echo, "#{capture("cd #{repo_path} && git describe --always --tags")} > version"
      end
    end
  end

  # Taken from https://github.com/rails/webpacker/blob/master/docs/deployment.md
  desc "Run rake yarn install"
  task :yarn_install do
    on roles(:web) do
      within release_path do
        execute("source ~/.nvm/nvm.sh && cd #{release_path} && yarn install --silent --no-progress --no-audit --no-optional")      end
    end
  end
end
