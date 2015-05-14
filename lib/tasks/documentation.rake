require 'rdoc/task'

namespace :doc do
  task :todo do
    # Files to exclude from TODO list
    exclude = [/Curry/, /dracula/, /lightbox/, /raphael/, /seedrandom/, /markdown/, /.png/, /jquery/]

    todo_file = File.open('doc/TODO', 'w')

    Dir.glob('app/**/*').each do |file|
      skip = false
      exclude.each do |exp|
        skip = true if exp.match(file)
      end
      next if skip

      next unless File.file?(file)
      File.open(file) do |f|
        counter = 0
        f.each_line do |line|
          begin
            if /TODO/.match(line)
              todo_file.write(file + ':' + counter.to_s + "::\t")
              todo_file.write(line)
            end
          rescue
            todo_file.write('Could not parse ' + file + '::')
          end
          counter += 1
        end
      end
    end
  end

  RDoc::Task.new('app') do |rdoc|
    Rake::Task['doc:todo'].invoke

    rdoc.rdoc_dir = 'doc/app'
    rdoc.title    = 'BlackLightning'
    rdoc.main     = 'doc/README' # define README_FOR_APP as index

    rdoc.options << '--charset' << 'utf-8'

    rdoc.rdoc_files.include('app/**/*.rb')
    rdoc.rdoc_files.include('lib/**/*.rb')
    rdoc.rdoc_files.include('config/initializers/*.rb')
    rdoc.rdoc_files.include('doc/TODO')
    rdoc.rdoc_files.include('doc/ADD_RESOUCES_PAGE')
  end
end
