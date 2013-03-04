set :deploy_to, "/srv/bedlamtheatre.co.uk/www"

role :web, "awe.mercuric.co.uk"                          # Your HTTP server, Apache/etc
role :app, "awe.mercuric.co.uk"                          # This may be the same as your `Web` server
role :db,  "awe.mercuric.co.uk", :primary => true        # This is where Rails migrations will run

set :rvm_ruby_string, "2.0.0@bedlamtheatre"
set :rvm_type, :system

after "deploy", "deploy:congratulate"

# before "deploy:setup", "rvm:install_pkgs"
# before "deploy:update", "rvm:create_gemset"

default_run_options[:shell] = '/bin/bash --login' # ?

require "rvm/capistrano"

namespace :deploy do
  task :congratulate do
    puts ""
    puts "Welcome to Production[new]."
  end
end
