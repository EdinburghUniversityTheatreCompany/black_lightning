set :deploy_to, "/var/www/dev_bedlamtheatre_co_uk"

# Set the bundler directory
set :bundle_dir, "/var/www/bedlamtheatre_co_uk/gems"
set :bundle_without, []

set :default_environment, {
    'GEM_HOME' => "/var/www/bedlamtheatre_co_uk/gems",
    'GEM_PATH' => "/var/www/bedlamtheatre_co_uk/gems",
}

after "deploy", "deploy:congratulate"

namespace :deploy do
  task :congratulate do
    puts ""
    puts "Welcome to Staging."
  end
end
