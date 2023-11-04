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
class MaintenanceAttendance < ApplicationRecord
  validates :maintenance_session, :user, presence: true

  belongs_to :user
  belongs_to :maintenance_session

  has_one :maintenance_debt, class_name: 'Admin::MaintenanceDebt', dependent: :nullify
  delegate :date, to: :maintenance_session
  
  def self.ransackable_attributes(auth_object = nil)
    %w[]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[user maintenance_session]
  end

  # Returns all maintenance attendances without a debt associated.
  def self.unassociated
    where.missing(:maintenance_debt)
  end

  # Associates itself with the soonest upcoming Maintenance Debt
  def associate_with_debt
    return unless maintenance_debt.nil?

    # TODO:Should search the soonest debt.
  end
end
