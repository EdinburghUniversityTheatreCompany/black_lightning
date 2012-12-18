set :deploy_to, "/var/www/dev_bedlamtheatre_co_uk"

after "deploy", "deploy:congratulate"

namespace :deploy do
  task :congratulate do
    puts ""
    puts "Welcome to Staging."
  end
end