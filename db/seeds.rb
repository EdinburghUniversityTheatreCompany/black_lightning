# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)

admin_user = User.create! :email => 'admin@bedlamtheatre.co.uk', :password => 'Passw0rd', :password_confirmation => 'Passw0rd'
admin_user.add_role :admin

test_user = User.create! :email => 'test@bedlamtheatre.co.uk', :password => 'Passw0rd', :password_confirmation => 'Passw0rd'
test_user.add_role :member