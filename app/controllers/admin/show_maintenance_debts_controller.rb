class Admin::ShowMaintenanceDebtsController < AdminController

  def create
    authorize! :create , Admin::MaintenanceDebt
    show = Show.find(params[:format])

    show.create_maintenance_debts

    redirect_to admin_show_path(show), notice: 'Obligations created.'
  end

end
