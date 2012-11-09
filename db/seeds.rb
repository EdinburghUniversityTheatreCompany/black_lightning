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

Show.create([
    {name: "Accidental Death of an Anarchist", slug: "accidental-death-of-an-anarchist", tagline: "A play by Dario Fo"},
    {name: "City of Cake", slug: "city-of-cake", tagline: "Cake! CAKE! THIS SHOW HAS CAKE!", xts_id: 419},
    {name: "Spring Awakening", slug: 'spring-awakening', tagline: "Performances as Teviot Debating Hall", xts_id: 423}
    ])

News.create([
    {title: "In the begining", slug: "begin", publish_date: (3).days.ago, show_public: true, body: "In the begining there was news.  \n And the news was rendered with *markdown*. And the Lord saw that it was good. \n \n He also noted that if you create two new lines, a new paragraph begins. \n \n Finally, he saw that only the first paragraph after 140 characters was displayed in the preview."},
    {title: "Then", slug: "then", publish_date: (2).days.ago, show_public: false, body: "Then the Lord saw that he could create news that was only displayed to members. He did test the system, and found that it was good."},
    {title: "Finally", slug: "finally", publish_date: (1).days.ago, show_public: true,  body: "This is some more news. That is all."}
    ])

Admin::EditableBlock.create([
    {name:"home_content", content: "Welcome to Project BlackLightning \n ==========================="}
    ])