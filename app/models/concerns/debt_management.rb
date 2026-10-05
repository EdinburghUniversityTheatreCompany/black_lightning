# frozen_string_literal: true

# An event's debt configuration: recommendations from its tags, and creating each team member's
# maintenance and staffing debts.
module DebtManagement
  extend ActiveSupport::Concern
  include AcademicYearHelper

  included do
    before_save :normalize_debt_amounts
  end

  def debt_configuration_active?
    maintenance_debt_amount.present? || staffing_debt_amount.present?
  end

  def tag_debt_recommendations
    @tag_debt_recommendations ||= event_tags.where.not(recommended_maintenance_debts: nil)
              .or(event_tags.where.not(recommended_staffing_debts: nil))
              .map do |tag|
      {
        tag_name: tag.name,
        maintenance: tag.recommended_maintenance_debts,
        staffing: tag.recommended_staffing_debts
      }
    end
  end

  def matches_tag_debt_recommendations?
    tag_debt_recommendations.any? do |rec|
      maintenance_debt_amount == rec[:maintenance] &&
      staffing_debt_amount == rec[:staffing]
    end
  end

  def debt_recommendation_status
    recs = tag_debt_recommendations
    return :no_recommendation if recs.empty?
    return :needs_config unless debt_configuration_active?
    return :matches if matches_tag_debt_recommendations?
    :mismatch
  end

  # Creates each team member's missing debts. Returns the counts created, { maintenance:, staffing: }.
  def sync_debts_for_all_users
    return { maintenance: 0, staffing: 0 } unless debt_configuration_active?
    return { maintenance: 0, staffing: 0 } unless end_date && end_date > start_of_year

    totals = { maintenance: 0, staffing: 0 }

    team_members.includes(:user).find_each do |team_member|
      result = sync_debts_for_team_member(team_member)
      totals[:maintenance] += result[:maintenance]
      totals[:staffing] += result[:staffing]
    end

    totals
  end

  def sync_debts_for_user(user)
    return { maintenance: 0, staffing: 0 } unless debt_configuration_active?
    return { maintenance: 0, staffing: 0 } unless maintenance_debt_start.present? || staffing_debt_start.present?
    return { maintenance: 0, staffing: 0 } unless end_date && end_date > start_of_year

    team_member = team_members.find_by(user: user)
    return { maintenance: 0, staffing: 0 } unless team_member

    sync_debts_for_team_member(team_member)
  end

  private

  # 0 and nil both mean "no debts".
  def normalize_debt_amounts
    self.maintenance_debt_amount = nil if maintenance_debt_amount == 0
    self.staffing_debt_amount = nil if staffing_debt_amount == 0
  end

  def sync_debts_for_team_member(team_member)
    user = team_member.user
    created = { maintenance: 0, staffing: 0 }

    if maintenance_debt_amount.present? && maintenance_debt_start.present?
      existing = user.admin_maintenance_debts.where(show: self).count
      needed = maintenance_debt_amount - existing

      needed.times do
        Admin::MaintenanceDebt.create!(
          show: self,
          user: user,
          due_by: maintenance_debt_start,
          state: :normal,
          converted_from_staffing_debt: false
        )
        created[:maintenance] += 1
      end
    end

    if staffing_debt_amount.present? && staffing_debt_start.present?
      existing = user.admin_staffing_debts.where(show: self).count
      amount = staffing_debt_amount_for_position(team_member.position, staffing_debt_amount)
      needed = amount - existing

      needed.times do
        Admin::StaffingDebt.create!(
          show: self,
          user: user,
          due_by: staffing_debt_start,
          state: :normal,
          converted_from_maintenance_debt: false
        )
        created[:staffing] += 1
      end
    end

    created
  end

  # Welfare as someone's only role owes no staffing; assistant roles alone owe at most one.
  def staffing_debt_amount_for_position(position, base_amount)
    roles = position.split("/").map(&:strip)

    return 0 if roles.length == 1 && roles.first.downcase.include?("welfare")

    if roles.all? { |role| role.downcase.include?("assistant") }
      return [ base_amount, 1 ].min
    end

    base_amount
  end
end
