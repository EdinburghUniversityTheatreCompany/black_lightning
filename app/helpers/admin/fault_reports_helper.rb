module Admin::FaultReportsHelper
  def fault_report_css_class(fault_report)
    case fault_report.status.to_sym
    when :in_progress, :on_hold
      return 'warning'
    when :cant_fix, :wont_fix
      return 'error'
    when :completed
      return 'success'
    else
      return ''
    end
  end
end
