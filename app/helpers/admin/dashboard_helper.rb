##
# Helper for the Admin Dashboard
##
module Admin::DashboardHelper
  ##
  # Displays the specified widget.
  #
  # Widgets should be stored in app/views/admin/dashboard, and should end with _widget
  # If you add a widget, please also add a test for the widget in the dahboard_helper_test.
  #
  # Rescues in case there is an error rendering the widget.
  ##
  def dashboard_widget(name)
    begin
      render "admin/dashboard/#{name}_widget"
    rescue ActionView::MissingTemplate
      # Update the tests if you change this message.
      "<div class=\"alert alert-danger\"><h3>Widget Not Found</h3><p>There is no widget with the name \"#{name}\"</p></div>".html_safe
    rescue => e
      # This only happens in the case of an epic fail, and cannot be properly tested
      # :nocov:
      "<div class=\"alert alert-danger\"><h3>Error During Rendering</h3><p>There was an error rendering the widget.</p><pre>#{e.message}</pre></div>".html_safe
      # :nocov:
    end
  end
end
