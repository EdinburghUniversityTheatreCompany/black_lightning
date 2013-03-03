set :deploy_to, "/srv/bedlamtheatre.co.uk/www"

role :web, "awe.mercuric.co.uk"                          # Your HTTP server, Apache/etc
role :app, "awe.mercuric.co.uk"                          # This may be the same as your `Web` server
role :db,  "awe.mercuric.co.uk", :primary => true        # This is where Rails migrations will run

after "deploy", "deploy:congratulate"

default_run_options[:shell] = '/bin/bash'

namespace :deploy do
  task :congratulate do
    puts ""
    puts "Welcome to Production[new]."
  end
end
