class Admin::DebtSummaryComponentPreview < Admin::ApplicationComponentPreview
  # Full debt summary for a user who is not in debt
  def default
    user = sample_user
    render Admin::DebtSummaryComponent.new(user: user, current_user: user)
  end

  # Compact (check-only) view shown when the viewer only has :check_debt permission
  def compact
    user = sample_user
    render Admin::DebtSummaryComponent.new(user: user, current_user: user, allow_compact: true)
  end
end
