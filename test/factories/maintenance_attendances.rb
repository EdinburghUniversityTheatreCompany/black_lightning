# == Schema Information
#
# Table name: maintenance_attendances
#
# *id*::                     <tt>bigint, not null, primary key</tt>
# *maintenance_session_id*:: <tt>bigint, not null</tt>
# *user_id*::                <tt>integer, not null</tt>
# *created_at*::             <tt>datetime, not null</tt>
# *updated_at*::             <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
FactoryBot.define do
  factory :maintenance_attendance do
    maintenance_session
    user
  end
end
