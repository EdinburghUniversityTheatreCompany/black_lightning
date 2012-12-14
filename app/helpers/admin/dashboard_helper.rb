##
# Helper for the Admin Dashboard
##
module Admin::DashboardHelper

  ##
  # Displays the specified widget.
  #
  # Widgets should be stored in app/views/admin/dashboard, and should end with _widget
  #
  # Rescues in case there is an error rendering the widget.
  ##
  def dashboard_widget(name)
    begin
      render "admin/dashboard/#{name}_widget"
    rescue => e
      return "<p>There was an error rendering the widget.</p><pre>#{e.message}</pre>".html_safe
    end
  end
end