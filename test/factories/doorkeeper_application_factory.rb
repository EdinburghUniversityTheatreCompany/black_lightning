# == Schema Information
#
# Table name: oauth_applications
#
# *id*::                  <tt>bigint, not null, primary key</tt>
# *name*::                <tt>string</tt>
# *uid*::                 <tt>string</tt>
# *secret*::              <tt>string</tt>
# *redirect_uri*::        <tt>text</tt>
# *scopes*::              <tt>string, default("")</tt>
# *confidential*::        <tt>boolean, default(TRUE)</tt>
# *created_at*::          <tt>datetime, not null</tt>
# *updated_at*::          <tt>datetime, not null</tt>
#--
# == Schema Information End
#++

FactoryBot.define do
  factory :doorkeeper_application, class: "Doorkeeper::Application" do
    name { Faker::Company.name }
    redirect_uri { "https://localhost:3001/callback" }
    scopes { "openid profile email" }
  end
end
