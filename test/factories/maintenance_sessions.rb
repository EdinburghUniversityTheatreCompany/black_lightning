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
      attendances = nil
      Thread.current[:bl_skip_debt_realloc] = true
      begin
        attendances = create_list(:maintenance_attendance, evaluator.attendances_count, maintenance_session: maintenance_session)
      ensure
        Thread.current[:bl_skip_debt_realloc] = nil
      end
      User.reallocate_maintenance_debts_for_users(attendances.map(&:user).uniq)
    end
  end
end
