# == Schema Information
#
# Table name: maintenance_credits
# Database name: primary
#
#  id                     :bigint           not null, primary key
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  maintenance_session_id :bigint           not null
#  user_id                :integer          not null
#
# Indexes
#
#  index_maintenance_credits_on_maintenance_session_id  (maintenance_session_id)
#  index_maintenance_credits_on_user_id                 (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class MaintenanceCredit < ApplicationRecord
  # Virtual, non-persisted. Used only by the maintenance session form: a representative credit
  # carries the user's credit count here so one row can stand in for N credits.
  # See MaintenanceSession#attendees_for_form and #maintenance_credits_attributes=.
  attr_accessor :quantity

  validates :maintenance_session, :user, presence: true

  belongs_to :user
  belongs_to :maintenance_session

  has_one :maintenance_debt, class_name: "Admin::MaintenanceDebt", dependent: :nullify
  delegate :date, to: :maintenance_session

  after_save :associate_with_debt
  after_destroy { associate_with_debt(true) }

  def self.ransackable_attributes(auth_object = nil)
    %w[]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[user maintenance_session]
  end

  # Returns all maintenance credits without a debt associated.
  def self.unassociated
    where.missing(:maintenance_debt)
  end

  # Associates itself with the soonest upcoming Maintenance Debt
  def associate_with_debt(skip_check = false)
    relevant_keys = previous_changes.keys.excluding("created_at", "updated_at")

    user.reallocate_maintenance_debts if skip_check || relevant_keys != [ "maintenance_debt_id" ]
  end
end
