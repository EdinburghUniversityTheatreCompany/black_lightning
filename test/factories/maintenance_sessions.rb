# == Schema Information
#
# Table name: maintenance_sessions
#
# *id*::         <tt>bigint, not null, primary key</tt>
# *date*::       <tt>date</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
#--
# == Schema Information End.
#++
FactoryBot.define do
  factory :maintenance_session do
    date { Date.current }

    transient do
      attendances_count { 2 }
    end

    after(:create) do |maintenance_session, evaluator|
      create_list(:maintenance_attendance, evaluator.attendances_count, maintenance_session: maintenance_session)
    end
  end
end
