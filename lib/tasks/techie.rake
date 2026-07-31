require "csv"
require "#{Rails.root}/lib/tasks/logic/techie"

namespace :techie do
  # simplecov:disable
  task :import, [ :file ] => :environment do |_t, args|
    p "Importing CSV file..."
    Tasks::Logic::Techie.import(args[:file])
    p "Imported all techies"
  end
  # simplecov:enable
end
