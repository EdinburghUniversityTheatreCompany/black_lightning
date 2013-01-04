set :deploy_to, "/var/www/dev_bedlamtheatre_co_uk"

# Set the bundler directory
set :bundle_dir, "/var/www/bedlamtheatre_co_uk/gems"
set :bundle_without, []

set :default_environment, {
    'GEM_HOME' => "/usr/local/rvm/gems/ruby-1.9.3-p362@global",
    'GEM_PATH' => "/usr/local/rvm/gems/ruby-1.9.3-p362@global"
}

after "deploy", "deploy:congratulate"

namespace :deploy do
  task :congratulate do
    puts ""
    puts "Welcome to Staging."
  end
end