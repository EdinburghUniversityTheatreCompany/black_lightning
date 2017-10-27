module Admin::MaintenanceDebtsHelper
  def staffing_debt_class(staffing_debt)
    case staffing_debt.status
      when :not_signed_up then
        "warning"
      when :awaiting_staffing then
        ""
      when :completed_staffing then
        "success"
      when :causing_debt then
        "error"
      when :forgiven then
        "success"
    end
  end

  def maintenance_debt_class(maintenance_debt)
    case maintenance_debt.status
      when :unfulfilled then
        "warning"
      when :converted then
        "success"
      when :completed then
        "success"
      when :causing_debt then
        "error"
    end
  end
end
