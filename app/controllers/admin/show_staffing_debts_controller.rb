class Admin::ShowStaffingDebtsController < AdminController
  def create
    authorize! :create , Admin::StaffingDebt
    show = Show.find(params[:format])
    show.create_staffing_debts(params[:number_of_slots_due][0].to_i)

    redirect_to admin_show_url(show), notice: 'Obligations created.'
  end

  def update
    show = Show.find(params[:id])

    #TODO check if this should be staffing_debt_start(2i)/ change to strong params
    if params[:show].length == 3 && params[:show][:'staffing_debt_start(1i)'].present? && params[:show][:'staffing_debt_start(3i)'].present? && params[:show][:'staffing_debt_start(3i)'].present?
      authorize! :create, Admin::StaffingDebt

      if show.update_attributes(params[:show])
        redirect_to admin_show_path(show), notice: 'Staffing Debt Start set'
      else
        redirect_to admin_show_path(show), notice: 'Error updating debt start please contact IT'
      end
    else
      redirect_to admin_show_path(show), notice: 'Error bad update request please contact IT'
    end
  end

end
