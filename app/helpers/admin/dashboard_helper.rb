module Admin::DashboardHelper
  def dashboard_widget(name)
    begin
      render "admin/dashboard/#{name}_widget"
    rescue => e
      return "<p>There was an error rendering the widget.</p><pre>#{e.message}</pre>".html_safe
    end
  end
end