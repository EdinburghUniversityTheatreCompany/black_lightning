class Admin::JobsController < AdminController
  before_action :authorize_manage_jobs!

  def authorize_manage_jobs!
    authorize!(:manage, :jobs)
  end
end
