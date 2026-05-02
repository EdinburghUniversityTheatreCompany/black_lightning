class Admin::DebtSummaryComponent < ViewComponent::Base
  def initialize(user:, current_user:, allow_compact: false)
    @user = user
    @current_user = current_user
    @allow_compact = allow_compact
  end

  def render?
    full_access? || check_only?
  end

  private

  def full_access?
    return @full_access if defined?(@full_access)
    @full_access = helpers.can?(:show, Admin::Debt.new(@user.id)) ||
      helpers.can?(:read, Admin::StaffingDebt.new(user_id: @user.id)) ||
      helpers.can?(:read, Admin::MaintenanceDebt.new(user_id: @user.id))
  end

  def check_only?
    return @check_only if defined?(@check_only)
    @check_only = @allow_compact && !full_access? && helpers.can?(:check_debt, Admin::Debt)
  end

  def card_variant
    if @user.in_debt
      :danger
    elsif has_upcoming?
      :warning
    else
      :success
    end
  end

  def status_badge_class
    if @user.in_debt
      "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800"
    elsif has_upcoming?
      "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800"
    else
      "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800"
    end
  end

  def status_label
    if @user.in_debt
      @user.debt_message_suffix.capitalize
    elsif has_upcoming?
      "Not in debt, but has upcoming unfulfilled debts"
    else
      "Not in debt"
    end
  end

  def tailwind_row_class(bootstrap_class)
    case bootstrap_class
    when "table-danger"  then "bg-red-50"
    when "table-warning" then "bg-yellow-50"
    when "table-success" then "bg-green-50"
    else ""
    end
  end

  def has_upcoming?
    @has_upcoming ||= upcoming_staffing.any? || upcoming_maintenance.any?
  end

  def upcoming_staffing
    @upcoming_staffing ||= @user.upcoming_staffing_debts
  end

  def upcoming_maintenance
    @upcoming_maintenance ||= @user.upcoming_maintenance_debts
  end

  def past_staffing
    @past_staffing ||= @user.debt_causing_staffing_debts
  end

  def past_maintenance
    @past_maintenance ||= @user.debt_causing_maintenance_debts
  end
end
