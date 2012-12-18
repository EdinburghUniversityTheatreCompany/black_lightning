require "delayed/recipes"

before "delayed_job:stop",    "deploy:chmoddj"
before "delayed_job:start",   "deploy:chmoddj"
before "delayed_job:restart", "deploy:chmoddj"

after "deploy:stop",    "delayed_job:stop"
after "deploy:start",   "delayed_job:start"
after "deploy:restart", "delayed_job:restart"

set :deploy_to, "/var/www/bedlamtheatre_co_uk"

desc "chmod delayed_job script"
task :chmoddj do
  run "chmod 775 #{current_path}/script/delayed_job"
end