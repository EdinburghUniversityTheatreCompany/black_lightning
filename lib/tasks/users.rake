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
  
  task :email do
    User.all.each do |u|
      begin
        UsersMailer.delay.welcome_email(u, true)
        puts "Just emailed #{u.name} at #{u.email}"
      rescue Exception => exc
        puts "Uh oh: #{u.name}, #{u.email} > #{exc.message}"
      end
    end
  end 

  task :interaction => :environment do
    percentage = 1 - (User.where(['sign_in_count = ?', 0]).count.to_f / User.all.count)
    puts "#{percentage} of users have set a password and signed in at least once."
  end

end