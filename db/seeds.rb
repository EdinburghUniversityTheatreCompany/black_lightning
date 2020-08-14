# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)

Role.create! name: :member
Role.create! name: :committee

admin_user = User.create! email: 'admin@bedlamtheatre.co.uk', password: 'Passw0rd', password_confirmation: 'Passw0rd'
admin_user.add_role :admin

test_user = User.create! email: 'test@bedlamtheatre.co.uk', password: 'Passw0rd', password_confirmation: 'Passw0rd'
test_user.add_role :member

# Necessary Editable Blocks

about = Admin::EditableBlock.create!              url: 'about', name: 'About', group: 'About'

get_invovled = Admin::EditableBlock.create!       url: 'get_involved',                name: 'Get Involved',   group: 'Get Involved'
about = Admin::EditableBlock.create!              url: 'get_involved/opportunities',  name: 'Opportunities',  group: 'Get Involved'

resources = Admin::EditableBlock.create!          url: 'admin/resources',                     name: 'Resources',          group: 'Resources'
membership_checker = Admin::EditableBlock.create! url: 'admin/resources/membership_checker',  name: 'Membership Checker', group: 'Resources'
