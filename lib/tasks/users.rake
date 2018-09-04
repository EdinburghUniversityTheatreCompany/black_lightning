require 'csv'
require 'json'
namespace :users do
  # desc 'Updates user attributes to match LDAP roles'
  # # N.B this also happens on sign in, but scheduling this as a cron job ensures
  # # things are relatively up to date all the while.
  # task update_attributes: :environment do
  #   User.find_each(&:update_ldap_attributes)
  # end

  # desc 'Import users from LDAP to black lightning'
  # task import_new_users: :environment do
  #   # Fetch all usernames from ldap
  #   connection = Devise::LDAP::Connection.new(admin: true)
  #   filter = Net::LDAP::Filter.eq('memberof', 'cn=members,cn=groups,cn=accounts,dc=bedlamtheatre,dc=co,dc=uk')
  #   ldap_users = connection.ldap.search(filter: filter)
  #   ldap_usernames = ldap_users.map(&:uid).flatten.map(&:downcase)

  #   # Find existing known usernames
  #   existing_usernames = User.pluck(:username)

  #   users_to_create = ldap_usernames - existing_usernames

  #   users_to_create.each do |username|
  #     puts "Importing #{username}"

  #     user = User.new(username: username)
  #     user.update_ldap_attributes
  #     user.save!
  #   end
  # end

  task interaction: :environment do
    all = User.all.count
    percentage = 1 - (User.where(['sign_in_count = ?', 0]).count.to_f / all)
    puts "#{percentage} of users have set a password and signed in at least once."
    phones = 1 - ((all - User.where(phone_number: nil).count.to_f) / all)
    puts "#{phones} of users have given us their phone number."
  end


end
