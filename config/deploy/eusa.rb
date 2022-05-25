server 'pineapple.eusa.ed.ac.uk', roles: %w(web app db), user: fetch(:user), password: fetch(:password)

set :stage, :eusa
set :deploy_to, '/srv/black_lightning'

set :rvm_ruby_string, '3.1.2@blacklightning'
set :rvm_type, :system
set :rvm_path, '/usr/local/rvm'

set :bundle_flags, '--quiet'
set :bundle_dir, ''

namespace :deploy do
  desc 'chmod delayed_job script'
  task :chmoddj do
    on roles(:app), in: :sequence, wait: 5 do
      within release_path do
        execute :chmod, '775', 'bin/delayed_job'
      end
    end
  end
end

before 'delayed_job:restart', 'deploy:chmoddj'

after 'deploy:restart', 'delayed_job:restart'
