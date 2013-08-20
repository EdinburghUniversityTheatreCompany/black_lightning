require "delayed/recipes"
require 'airbrake/capistrano'
require "rvm/capistrano"

role :web, "pineapple.eusa.ed.ac.uk"
role :app, "pineapple.eusa.ed.ac.uk"
role :db, "pineapple.eusa.ed.ac.uk", :primary=>true

before "delayed_job:stop",    "deploy:chmoddj"
before "delayed_job:start",   "deploy:chmoddj"
before "delayed_job:restart", "deploy:chmoddj"

after "deploy:stop",    "delayed_job:stop"
after "deploy:start",   "delayed_job:start"
after "deploy:restart", "delayed_job:restart"

set :deploy_to, "/srv/black_lightning"

set :rvm_ruby_string, "2.0.0@blacklightning"
set :rvm_type, :system
set :rvm_path, "/usr/local/rvm"

set :bundle_flags, "--quiet"
set :bundle_dir, ""

namespace :deploy do
  desc "chmod delayed_job script"
  task :chmoddj do
    run "chmod 775 #{current_path}/script/delayed_job"
  end
end