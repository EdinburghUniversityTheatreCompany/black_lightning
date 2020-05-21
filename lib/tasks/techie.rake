require 'csv'
require "#{Rails.root}/lib/tasks/logic/techie_task_logic"

namespace :techie do
  # :nocov:
  task :import, [:file] => :environment do |_t, args|
    p 'Importing CSV file...'
    TechieTaskLogic.import(args[:file])
    p 'Imported all techies'
  end
  # :nocov:
end
