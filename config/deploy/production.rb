require "delayed/recipes"

before "deploy", "check_tag"

before "delayed_job:stop",    "deploy:chmoddj"
before "delayed_job:start",   "deploy:chmoddj"
before "delayed_job:restart", "deploy:chmoddj"

after "deploy:stop",    "delayed_job:stop"
after "deploy:start",   "delayed_job:start"
after "deploy:restart", "delayed_job:restart"

set :deploy_to, "/var/www/bedlamtheatre_co_uk"

set :branch do
  tag = `git describe`

  confirm = Capistrano::CLI.ui.ask "Tag to deploy (make sure to push the tag first): #{tag}. Please confirm. [N]"
  confirm = "N" if confirm.empty?

  unless ["Y", "y"].include? confirm
    raise CommandError.new("Deploy Cancelled.")
  end

  next tag
end

namespace :deploy do
  desc "chmod delayed_job script"
  task :chmoddj do
    run "chmod 775 #{current_path}/script/delayed_job"
  end
end

task :check_tag do
  # Returns false if no tag exists, since git quits with an error.
  if not system 'git describe --exact-match'
    raise CommandError.new("Please tag commits before deploying to production.")
  end
end