require 'csv'
require 'json'
namespace :users do
  task :import, [:file] => :environment do |t, args|
    CSV.foreach(args[:file]) do |row|
      begin
        u = User.create_user(first_name: row[1], last_name: row[2], email: row[0])
        puts "Just added #{u.name}"
      rescue Exception => exc
        puts "Uh oh: #{row[1]} #{row[2]}, #{exc.message}"
      end
    end
  end
end