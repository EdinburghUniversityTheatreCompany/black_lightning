# frozen_string_literal: true

##
# DebtManagement concern provides debt configuration and synchronization
# functionality for all Event types (Shows, Workshops, Seasons, etc.)
#
# This concern handles:
# - Debt configuration validation
# - Tag-based debt recommendations
# - Automatic debt creation for team members
# - Position-based debt amount adjustments (Assistants, Welfare)
##
module DebtManagement
  extend ActiveSupport::Concern
  include AcademicYearHelper

  included do
    before_save :normalize_debt_amounts
  end

  ##
  # Returns true if this event has debt amounts configured
  ##
  def debt_configuration_active?
    maintenance_debt_amount.present? || staffing_debt_amount.present?
  end

  ##
  # Returns debt recommendations from associated event tags
  # Returns array of hashes with tag_name, maintenance, and staffing amounts
  ##
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

  ##
  # Returns true if current debt configuration matches any tag recommendation
  ##
  def matches_tag_debt_recommendations?
    tag_debt_recommendations.any? do |rec|
      maintenance_debt_amount == rec[:maintenance] &&
      staffing_debt_amount == rec[:staffing]
    end
  end

  ##
  # Returns the debt recommendation status as a symbol:
  # - :no_recommendation - no tags with recommendations
  # - :needs_config - has recommendations but debt not configured
  # - :matches - configured and matches a recommendation
  # - :mismatch - configured but doesn't match recommendations
  ##
  def debt_recommendation_status
    recs = tag_debt_recommendations
    return :no_recommendation if recs.empty?
    return :needs_config unless debt_configuration_active?
    return :matches if matches_tag_debt_recommendations?
    :mismatch
  end

  ##
  # Synchronizes debts for all team members on this event
  # Creates missing debts based on configured amounts
  # Returns hash with counts: { maintenance: X, staffing: Y }
  ##
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

  ##
  # Synchronizes debts for a specific user on this event
  # Creates missing debts based on configured amounts
  # Returns hash with counts: { maintenance: X, staffing: Y }
  ##
  def sync_debts_for_user(user)
    return { maintenance: 0, staffing: 0 } unless debt_configuration_active?
    return { maintenance: 0, staffing: 0 } unless maintenance_debt_start.present? || staffing_debt_start.present?
    return { maintenance: 0, staffing: 0 } unless end_date && end_date > start_of_year

    team_member = team_members.find_by(user: user)
    return { maintenance: 0, staffing: 0 } unless team_member

    sync_debts_for_team_member(team_member)
  end

  private

  ##
  # Normalizes debt amounts by converting 0 to nil
  # This ensures consistent behavior where 0 and nil both mean "no debts"
  ##
  def normalize_debt_amounts
    self.maintenance_debt_amount = nil if maintenance_debt_amount == 0
    self.staffing_debt_amount = nil if staffing_debt_amount == 0
  end

  ##
  # Creates missing debts for a specific team member
  # Applies position-based rules for staffing debts
  # Returns hash with counts: { maintenance: X, staffing: Y }
  ##
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

  ##
  # Calculates staffing debt amount based on position roles
  # Rules:
  # - Welfare only (single role): 0 debts
  # - All roles are assistants: max 1 debt
  # - Otherwise: full base_amount
  ##
  def staffing_debt_amount_for_position(position, base_amount)
    roles = position.split("/").map(&:strip)

    # Welfare only if it's their ONLY role
    return 0 if roles.length == 1 && roles.first.downcase.include?("welfare")

    # Assistant cap only if ALL roles are assistant roles
    if roles.all? { |role| role.downcase.include?("assistant") }
      return [ base_amount, 1 ].min
    end

    base_amount
  end
end
