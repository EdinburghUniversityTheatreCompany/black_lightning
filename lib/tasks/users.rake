require 'csv'
require 'json'
namespace :users do
  task :import, [:file, :send_email] => :environment do |t, args|
    puts "Importing users from #{args[:file]} and #{"not " if args[:send_email] != "true"}sending welcome emails."

    CSV.foreach(args[:file]) do |row|
      begin
        u = User.create_user(first_name: row[1], last_name: row[2], email: row[0])

        UsersMailer.delay.welcome_email(u, true) if args[:send_email] == "true"

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
    all = User.all.count
    percentage = 1 - (User.where(['sign_in_count = ?', 0]).count.to_f / all)
    puts "#{percentage} of users have set a password and signed in at least once."
    phones = 1 - ((all - User.where(phone_number: nil).count.to_f) / all)
    puts "#{phones} of users have given us their phone number."
  end

end