set :deploy_to, "/home/bedlamtheatre/staging"

role :web, "lomond.mercuric.co.uk"                          # Your HTTP server, Apache/etc
role :app, "lomond.mercuric.co.uk"                          # This may be the same as your `Web` server
role :db,  "lomond.mercuric.co.uk", :primary => true        # This is where Rails migrations will run

# Set the bundler directory
set :bundle_dir, "/var/www/bedlamtheatre_co_uk/gems"
set :bundle_without, []

set :default_environment, {
    'GEM_HOME' => "/var/www/bedlamtheatre_co_uk/gems",
    'GEM_PATH' => "/var/www/bedlamtheatre_co_uk/gems"
}



after "deploy", "deploy:congratulate"

namespace :deploy do
  task :congratulate do
    puts ""
    puts "Welcome to Lomond Staging."
  end
end