class Admin::ShowMaintenanceDebtsController < AdminController

  def create
    authorize! :create, Admin::MaintenanceDebt
    show = Show.find(params[:format])

    show.create_maintenance_debts

    redirect_to admin_show_path(show), notice: 'Obligations created.'
  end

  def update
    show = Show.find(params[:id])

    #TODO check if this should be maintenance_debt_start(2i)/ change to strong params
    if params[:show].length == 3 && params[:show][:'maintenance_debt_start(1i)'].present? && params[:show][:'maintenance_debt_start(3i)'].present? && params[:show][:'maintenance_debt_start(3i)'].present?
      authorize! :create, Admin::MaintenanceDebt

      if show.update_attributes(params[:show])
        redirect_to admin_show_path(show), notice: 'Maintenance Debt Start set'
      else
        redirect_to admin_show_path(show), notice: 'Error please contact IT'
      end
    else
      redirect_to admin_show_path(show), notice: 'Error please contact IT'
    end

  end

end
