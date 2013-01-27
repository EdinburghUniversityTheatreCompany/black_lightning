require 'reek/rake/task'

Reek::Rake::Task.new do |t|
  t.fail_on_error = false
  t.source_files  = 'app/{controllers,helpers,mailers,models}/**/*.rb'
  t.reek_opts     = "--quiet"
end