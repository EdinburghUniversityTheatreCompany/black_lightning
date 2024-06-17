namespace :users_to_ldap do
  # :nocov:
  task :migrate => :environment do
    base = 'cn=users,cn=accounts,dc=bedlamtheatre,dc=co,dc=uk'


    auth = { method: :simple, username: Rails.application.credentials[:ldap][Rails.env.to_sym][:bind_user], password: Rails.application.credentials[:ldap][Rails.env.to_sym][:bind_pass] }
    migration = LdapMigration.new(host: 'ldap.bedlamtheatre.co.uk', port: 389, base: 'cn=users,cn=accounts,dc=bedlamtheatre,dc=co,dc=uk', auth: auth)
    users = User.all.order('id ASC')

    users.each do |user|
      remote = migration.fetch_by_email(user.email)

      migration.filters.each do |filter|
        user, remote = migration.send(filter, user, remote)
        user.save!
      end
    end
  end
  # :nocov:
end
