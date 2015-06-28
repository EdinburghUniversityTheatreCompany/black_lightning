namespace :users_to_ldap do
  task :migrate => :environment do
    base = 'cn=users,cn=accounts,dc=bedlamtheatre,dc=co,dc=uk'


    auth = { method: :simple, username: Rails.application.secrets.ldap['bind_user'], password: Rails.application.secrets.ldap['bind_pass'] }
    migration = LDAPMigration.new(host: 'ldap.bedlamtheatre.co.uk', port: 389, base: 'cn=users,cn=accounts,dc=bedlamtheatre,dc=co,dc=uk', auth: auth)
    users = User.all.order('id ASC')

    users.each do |user|
      remote = migration.fetch_by_email(user.email)

      migration.filters.each do |filter|
        user, remote = migration.send(filter, user, remote)
      end
    end
  end
end
