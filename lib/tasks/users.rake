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
  #     p "Importing #{username}"

  #     user = User.new(username: username)
  #     user.update_ldap_attributes
  #     user.save!
  #   end
  # end

  # :nocov:
  task interaction: :environment do
    all = User.all.count
    p "We have #{User.all.count} users, of which #{User.with_role(:member).count} are members"
    percentage = 1 - (User.where(['sign_in_count = ?', 0]).count.to_f / all)
    p "#{percentage} of users have set a password and signed in at least once."
    phones = 1 - ((all - User.where(phone_number: nil).count.to_f) / all)
    p "#{phones} of users have given us their phone number."
  end
  # :nocov:

  task clean_up_personal_info: :environment do
    p 'Cleaning up personal info..'
    count = Tasks::Logic::Users::clean_up_personal_info
    p "Cleaned up #{count} members"
  end

  desc 'Lists the amount of users who were involved in an event or listed on a proposal during each academic year.'
  task determine_active_users_by_involvement: :environment do
    p 'Academic Year, Total Members, Fresher\'s Play Only, Proposal Only'
    (Rails.configuration.start_year..Date.today.year).each do |start_year|
      start_date = Date.new(start_year, 9, 1)
      end_date = Date.new(start_year + 1, 8, 31)

      # Determine who was involved in an event
      events = Event.where('start_date <= ? and end_date >= ?', end_date, start_date)
      events_user_ids = events.flat_map { |event| event.users.ids }.uniq

      # Determine who was involved in an event that is not freshers play.
      other_events = events.where.not("name like '%fresher%'")
      other_events_user_ids = other_events.flat_map { |event| event.users.ids }.uniq
      # Freshers-only are the people who participated in events, but not in other events.
      freshers_only_user_ids = events_user_ids - other_events_user_ids

      # Determine who was on proposals, and who only was on a proposal.
      proposals = Admin::Proposals::Proposal.includes(:call).where(call: { submission_deadline: start_date..end_date })
      proposals_user_ids = proposals.flat_map { |event| event.users.ids }.uniq
      proposals_only_user_ids = proposals_user_ids - events_user_ids

      # Sum everyone.
      user_ids = (events_user_ids + proposals_user_ids).uniq

      p("#{start_date.year}-#{end_date.year}, #{user_ids.size}, #{freshers_only_user_ids.size}, #{proposals_only_user_ids.size}")
    end
  end
end
