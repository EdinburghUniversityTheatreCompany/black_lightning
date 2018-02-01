module Admin::FaultReportsHelper
  def fault_report_class(fault_report)
    case fault_report.status.to_s
    when "in_progress", "on_hold"
      "warning"
    when "cant_fix", "wont_fix"
      "error"
    when "completed"
      "success"
    else
      ""
    end
  end
end
