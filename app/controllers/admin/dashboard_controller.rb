class Admin::DashboardController < AdminController
  def index
    @title = 'Dashboard'
  end

  # This only exists for testing, and it is only accessible in the dev and test environment.
  def widget
    @widget_name = params[:widget_name]
  end
end
