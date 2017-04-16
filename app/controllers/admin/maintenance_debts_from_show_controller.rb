class Admin::MaintenanceDebtsFromShowController < AdminController

  def create
    authorize! :create , Admin::MaintenanceDebt
    show = Show.find(params[:format])

    show.create_mdebts

    redirect_to admin_show_url(show), notice: 'Obligations created.'
  end

end
