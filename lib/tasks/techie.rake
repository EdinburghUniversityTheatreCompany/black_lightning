require 'csv'
namespace :techie do
  task :import, [:file] => :environment do |_t, args|
    CSV.foreach(args[:file]) do |row|
      if Techie.where(name: row[0]).count == 0
        p = Techie.new(name: row[0])
        p.save
      else
        p = Techie.where(name: row[0]).first
      end
      if Techie.where(name: row[1]).count == 0
        c = Techie.new(name: row[1])
        c.save
      else
        c = Techie.where(name: row[1]).first
      end
      p.children << c
      p.save
    end
  end
end
