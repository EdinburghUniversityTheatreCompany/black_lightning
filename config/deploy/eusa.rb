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


namespace :deploy do
  task :congratulate do
    puts ""
    puts "Welcome to Production on EUSA Pineapple."
  end
  
  task :restart, :except => { :no_release => true } do
    run "kill -s USR2 `cat /tmp/unicorn.bedlamtheatre.pid`"
  end

  task :start, :except => {:no_release => true } do
    run "cd #{current_path} ; bundle exec unicorn_rails -c config/unicorn.rb -D"
  end
  
end
