module Admin::MaintenanceDebtsHelper
  def staffing_debt_class(staffing_debt)
    out = case staffing_debt.status
            when :not_signed_up then "warning"
            when :awaiting_staffing then ""
            when :completed_staffing then "success"
            when :causing_debt then "error"
          end
    return out
  end
end
