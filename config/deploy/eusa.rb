set :deploy_to, "/srv/blacklightning"

role :web, "pineapple.eusa.ed.ac.uk"                          # Your HTTP server, Apache/etc
role :app, "pineapple.eusa.ed.ac.uk"                          # This may be the same as your `Web` server
role :db,  "pineapple.eusa.ed.ac.uk", :primary => true        # This is where Rails migrations will run

set :rvm_ruby_string, "2.0.0@blacklightning"
set :rvm_type, :system
set :rvm_path, "/usr/local/rvm"

set :bundle_flags, "--quiet"
set :bundle_dir, ""


after "deploy", "deploy:restart"
after "deploy", "deploy:congratulate"

# before "deploy:setup", "rvm:install_pkgs"
# before "deploy:update", "rvm:create_gemset"

require "rvm/capistrano"

require "capistrano-unicorn"

after 'deploy:restart', 'unicorn:reload' # app IS NOT preloaded
after 'deploy:restart', 'unicorn:restart'  # app preloaded

namespace :deploy do
  task :congratulate do
    puts ""
    puts "Welcome to Production on EUSA Pineapple."
  end
    
end
